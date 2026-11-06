// Sources/mtats/StatusBarController.swift
// SPDX-License-Identifier: MIT
import AppKit
import SwiftUI
import MTatsPluginKit

/// An NSObject because the ⚙ status item sends its click to `self` via target/action; AppKit can
/// only dispatch that to an NSObject that responds to the selector. As a plain Swift class the
/// click was silently dropped and Settings never opened.
public final class StatusBarController: NSObject {
    /// One per widget; lives in its own status item, or inside `combinedItem` in combined mode.
    private final class Slot {
        let widget: MTatsWidget
        let hosting: PassthroughHostingView<AnyView>
        let popover = NSPopover()
        var item: NSStatusItem?
        /// Grow-only content width, so a value changing digit count doesn't shift items to its left.
        var contentWidth: CGFloat = 0
        init(widget: MTatsWidget, hosting: PassthroughHostingView<AnyView>) { self.widget = widget; self.hosting = hosting }
    }
    private var slots: [String: Slot] = [:]
    private var slotOrder: [String] = []
    private var widgets: [MTatsWidget] = []
    private var combinedItem: NSStatusItem?
    private var gearHosting: PassthroughHostingView<AnyView>?
    /// Set when macOS hid one of our items; cleared when the display configuration changes.
    private var autoCombined = false
    private var isCombined = false
    private var hiddenDebounce = HiddenDebounce()
    private var visibilityTimer: Timer?
    private var screensAsleep = false
    /// Interval each widget was last started at; absent means stopped.
    private var runningIntervals: [String: TimeInterval] = [:]
    private var settingsItem: NSStatusItem?
    private var settingsWindow: NSWindow?
    private let settings: SettingsStore
    private let loader: PluginLoader
    private let updateControls: UpdateControls?

    public init(settings: SettingsStore, loader: PluginLoader, updateControls: UpdateControls? = nil) {
        self.settings = settings
        self.loader = loader
        self.updateControls = updateControls
        super.init()
    }

    /// Call again with an expanded widget list (e.g. after the FSEvents watcher in
    /// PluginLoader reports a newly-installed third-party plugin) — existing items for
    /// widgets already presented are left alone; only genuinely new widgets get a new item.
    public func present(widgets: [MTatsWidget]) {
        let alreadyPresentedIDs = Set(self.widgets.map(\.id))
        let newWidgets = widgets.filter { !alreadyPresentedIDs.contains($0.id) }
        guard !newWidgets.isEmpty else { return }
        self.widgets.append(contentsOf: newWidgets)

        for widget in newWidgets {
            // Sized from the rendered content, not per-widget constants: the Host has no
            // built-in knowledge of specific widgets (spec §4.1), and third-party widgets
            // need room too. NSStatusItem.squareLength/.variableLength are sentinels (-2/-1),
            // never usable as view dimensions.
            let hosting = PassthroughHostingView(rootView: widget.menuBarView())
            let slot = Slot(widget: widget, hosting: hosting)
            hosting.onLayout = { [weak self, weak slot, weak hosting] in
                guard let self, let slot, let hosting else { return }
                let grown = max(slot.contentWidth, hosting.fittingSize.width.rounded(.up))
                if grown != slot.contentWidth {
                    slot.contentWidth = grown
                    self.relayout()
                }
            }

            // Every dropdown carries a Settings button: if macOS hides the ⚙ item, any visible indicator
            // is still a way in.
            let detail = NSHostingController(rootView: VStack(spacing: 0) {
                widget.detailView()
                Divider()
                HStack { Button("Settings…") { [weak self] in self?.showSettings() }.buttonStyle(.link); Spacer() }
                    .padding(.horizontal, 12).padding(.vertical, 6)
            })
            // Let the popover take the detail view's size, so content isn't clipped and the
            // arrow sits over the status item instead of drifting to a fixed default size.
            detail.sizingOptions = [.preferredContentSize]
            slot.popover.contentViewController = detail
            slot.popover.behavior = .transient
            PopoverShower.shared.track(slot.popover)

            slots[widget.id] = slot
            slotOrder.append(widget.id)
            slot.contentWidth = hosting.fittingSize.width.rounded(.up)
            attach(slot)
            // Apply the public-IP toggle before start() — start() can fire an immediate
            // lookup, and doing that before the toggle is applied would ignore a user who
            // has it turned off (a privacy-relevant external call per spec §6).
            if let toggleable = widget as? PublicIPToggleable {
                toggleable.setPublicIPLookupEnabled(settings.publicIPLookupEnabled)
            }
            apply(to: widget)
        }

        if settingsItem == nil { presentSettingsMenuItem(); startVisibilityMonitor() }
        refreshLayout()
        // An already-open Settings window captured the old widget list; rebuild it so a
        // hot-loaded plugin gets its toggle immediately.
        settingsWindow?.contentView = NSHostingView(rootView: makeSettingsView())
    }

    /// spec §6: disabling a Widget must make it disappear from the menu bar, not just stop
    /// updating. Only widgets whose enabled state or the refresh interval actually changed are
    /// touched — restarting everything on any toggle wipes sampling baselines and makes the
    /// Network widget re-hit the public-IP service.
    public func applyEnabledState() {
        for widget in widgets {
            if let toggleable = widget as? PublicIPToggleable {
                toggleable.setPublicIPLookupEnabled(settings.publicIPLookupEnabled)
            }
            apply(to: widget)
        }
        refreshLayout()
    }

    private func apply(to widget: MTatsWidget) {
        let enabled = settings.isEnabled(widgetID: widget.id)
        switch WidgetLifecycle.action(runningInterval: runningIntervals[widget.id], enabled: enabled, interval: settings.refreshInterval) {
        case .start(let interval):
            widget.start(interval: interval)
            runningIntervals[widget.id] = interval
        case .stop:
            widget.stop()
            runningIntervals[widget.id] = nil
        case .none:
            break
        }
    }

    private func makeSettingsView() -> SettingsView {
        SettingsView(settings: settings, widgets: widgets, loader: loader, updateControls: updateControls, onToggle: { [weak self] in self?.applyEnabledState() })
    }

    // MARK: - Layout (separate items vs one combined item)

    private func enabledSlots() -> [Slot] {
        slotOrder.compactMap { slots[$0] }.filter { settings.isEnabled(widgetID: $0.widget.id) }
    }

    /// Decides the mode, then lays everything out. Cheap; called on any change.
    private func refreshLayout() {
        let want = settings.combineMenuBarItems || autoCombined
        if want != isCombined { setCombined(want) } else { relayout() }
    }

    private func setCombined(_ combined: Bool) {
        PopoverShower.shared.closeAll()
        isCombined = combined
        if combined, combinedItem == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            item.button?.target = self
            item.button?.action = #selector(combinedClicked(_:))
            combinedItem = item
        }
        if combined, gearHosting == nil {
            let gear = PassthroughHostingView(rootView: AnyView(Text("⚙")))
            gearHosting = gear
        }
        for id in slotOrder { if let slot = slots[id] { attach(slot) } }
        if let gear = gearHosting {
            gear.removeFromSuperview()
            if combined { combinedItem?.button?.addSubview(gear) }
        }
        relayout()
    }

    /// Puts a slot's view in the right status item for the current mode.
    private func attach(_ slot: Slot) {
        slot.hosting.removeFromSuperview()
        if isCombined {
            slot.item.map { NSStatusBar.system.removeStatusItem($0) }
            slot.item = nil
            combinedItem?.button?.addSubview(slot.hosting)
        } else {
            if slot.item == nil {
                let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
                item.button?.target = PopoverShower.shared
                item.button?.action = #selector(PopoverShower.toggle(_:))
                slot.item = item
            }
            if let button = slot.item?.button {
                button.addSubview(slot.hosting)
                PopoverShower.shared.register(button: button, popover: slot.popover, anchor: slot.hosting)
            }
        }
    }

    private func relayout() {
        let enabled = enabledSlots()
        for slot in slots.values { slot.hosting.isHidden = !enabled.contains { $0 === slot } }
        let height = NSStatusBar.system.thickness
        if isCombined {
            settingsItem?.isVisible = false
            combinedItem?.isVisible = true
            var widths = enabled.map(\.contentWidth)
            let gearWidth = gearHosting.map { $0.fittingSize.width.rounded(.up) } ?? 0
            widths.append(gearWidth)
            let layout = MenuBarFit.layout(widths: widths)
            for (slot, x) in zip(enabled, layout.offsets) {
                let frame = NSRect(x: x, y: 0, width: slot.contentWidth, height: height)
                if slot.hosting.frame != frame { slot.hosting.frame = frame }
            }
            if let gear = gearHosting, let x = layout.offsets.last {
                let frame = NSRect(x: x, y: 0, width: gearWidth, height: height)
                if gear.frame != frame { gear.frame = frame }
            }
            if combinedItem?.length != layout.total { combinedItem?.length = layout.total }
        } else {
            combinedItem?.isVisible = false
            settingsItem?.isVisible = true
            for slot in slots.values {
                let enabled = settings.isEnabled(widgetID: slot.widget.id)
                slot.item?.isVisible = enabled
                let width = slot.contentWidth + WidgetLifecycle.itemPadding
                if slot.item?.length != width { slot.item?.length = width }
                let frame = NSRect(x: WidgetLifecycle.itemPadding / 2, y: 0, width: slot.contentWidth, height: height)
                if slot.hosting.frame != frame { slot.hosting.frame = frame }
            }
        }
    }

    /// Click on the combined item: work out which indicator was hit and open its popover.
    @objc private func combinedClicked(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }
        let point = sender.convert(event.locationInWindow, from: nil)
        if let gear = gearHosting, gear.frame.contains(point) { openSettings(); return }
        let enabled = enabledSlots()
        let hit = enabled.first { $0.hosting.frame.insetBy(dx: -MenuBarFit.slotGap / 2, dy: 0).contains(point) } ?? enabled.last
        guard let slot = hit else { return }
        PopoverShower.shared.toggle(popover: slot.popover, relativeTo: slot.hosting)
    }

    // MARK: - Noticing that macOS hid us

    private func startVisibilityMonitor() {
        let timer = Timer(timeInterval: 3, repeats: true) { [weak self] _ in self?.checkVisibility() }
        RunLoop.main.add(timer, forMode: .common)
        visibilityTimer = timer
        let center = NotificationCenter.default
        center.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            // New display layout (docked, lid, resolution): start over with separate items and re-measure.
            guard let self else { return }
            self.hiddenDebounce.reset()
            if self.autoCombined { self.autoCombined = false; self.refreshLayout() }
        }
        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in self?.screensAsleep = true }
        workspace.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.screensAsleep = false
            self?.hiddenDebounce.reset()
        }
    }

    private func visibleItemIsHidden(_ item: NSStatusItem?) -> Bool? {
        guard let item, item.isVisible, let window = item.button?.window else { return item?.isVisible == true ? true : nil }
        guard let screen = window.screen ?? NSScreen.main else { return true }
        // No menu bar on this screen right now (full-screen app, auto-hide): nothing to judge.
        guard screen.frame.maxY - screen.visibleFrame.maxY >= 1 else { return nil }
        let usable = MenuBarFit.usableArea(screenFrame: screen.frame, rightOfNotch: screen.auxiliaryTopRightArea)
        return MenuBarFit.isHidden(itemFrame: window.frame, hasScreen: window.screen != nil, usable: usable)
    }

    private func checkVisibility() {
        guard !screensAsleep, !autoCombined, !settings.combineMenuBarItems else { return }
        let candidates = slotOrder.compactMap { slots[$0]?.item } + [settingsItem]
        let verdicts = candidates.compactMap(visibleItemIsHidden)
        guard !verdicts.isEmpty else { return }
        if hiddenDebounce.record(hidden: verdicts.contains(true)) {
            autoCombined = true
            refreshLayout()
        }
    }

    /// spec §6 requires Settings to actually be reachable. A small "⚙" status item is the
    /// simplest way to do that for v1 — no Dock icon (LSUIElement), so there's no menu bar
    /// "app menu" to hang a Settings item off of otherwise.
    private func presentSettingsMenuItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.title = "⚙"
        item.button?.target = self
        item.button?.action = #selector(openSettings)
        settingsItem = item
    }

    /// Also reached by launching the app again (Spotlight/Finder) while it is already running.
    public func showSettings() { openSettings() }

    @objc private func openSettings() {
        if settingsWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 360, height: 280), styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = "mtats Settings"
            window.contentView = NSHostingView(rootView: makeSettingsView())
            window.isReleasedWhenClosed = false
            settingsWindow = window
        }
        // An LSUIElement app is never frontmost, and a plain `activate()` is cooperative: it doesn't
        // take focus from the app you're in, so the window opened *behind* Chrome and looked like
        // the click did nothing (verified with a window-order probe). Bring it forward explicitly.
        if let window = settingsWindow {
            let anchorWindow = (isCombined ? combinedItem : settingsItem)?.button?.window
            if let anchor = anchorWindow?.frame, let visible = (anchorWindow?.screen ?? NSScreen.main)?.visibleFrame {
                window.setFrameOrigin(SettingsPlacement.origin(size: window.frame.size, below: anchor, in: visible))
            } else {
                window.center()
            }
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        settingsWindow?.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
    }
}

/// NSView's default hit-testing claims any click inside its bounds, including a plain
/// non-interactive SwiftUI Text — which would swallow clicks meant for the NSStatusBarButton
/// hosting it (the popover toggle would never fire). Returning nil lets the click pass through.
/// Also reports each layout pass so the status item can grow when the SwiftUI content gets
/// wider. (Overriding invalidateIntrinsicContentSize doesn't work for this: NSHostingView
/// doesn't route content-size changes through it — verified with a status-item probe.)
private final class PassthroughHostingView<Content: View>: NSHostingView<Content> {
    var onLayout: (() -> Void)?
    private var isReporting = false
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func layout() {
        super.layout()
        // Resizing inside the callback triggers another layout pass; don't recurse.
        guard !isReporting else { return }
        isReporting = true
        onLayout?()
        isReporting = false
    }
}

/// Shared target/action so each status item's button can toggle its own popover, and so a click
/// anywhere else on screen dismisses it. `.transient` alone doesn't: for an accessory (no Dock icon)
/// app, clicks on the desktop or in another app's window don't reliably close the popover.
private final class PopoverShower: NSObject, NSPopoverDelegate {
    static let shared = PopoverShower()
    private var tracked: [NSPopover] = []
    private var byButton: [ObjectIdentifier: (popover: NSPopover, anchor: NSView)] = [:]
    private var clickAwayMonitor: Any?

    func track(_ popover: NSPopover) {
        guard !tracked.contains(where: { $0 === popover }) else { return }
        tracked.append(popover)
        popover.delegate = self
    }

    func register(button: NSStatusBarButton, popover: NSPopover, anchor: NSView) {
        byButton[ObjectIdentifier(button)] = (popover, anchor)
    }

    @objc func toggle(_ sender: NSStatusBarButton) {
        guard let entry = byButton[ObjectIdentifier(sender)] else { return }
        toggle(popover: entry.popover, relativeTo: entry.anchor)
    }

    func toggle(popover: NSPopover, relativeTo anchor: NSView) {
        if popover.isShown {
            popover.performClose(nil)
            return
        }
        closeAll() // one open at a time
        popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .minY)
        installClickAwayMonitor()
    }

    func popoverDidClose(_ notification: Notification) {
        if !tracked.contains(where: \.isShown) { removeClickAwayMonitor() }
    }

    func closeAll() {
        for popover in tracked where popover.isShown { popover.performClose(nil) }
    }

    /// Global monitors only see events destined for *other* apps, so a click on one of our own
    /// status buttons never reaches this handler and can't double-toggle.
    private func installClickAwayMonitor() {
        guard clickAwayMonitor == nil else { return }
        clickAwayMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
            self?.closeAll()
        }
    }

    private func removeClickAwayMonitor() {
        if let monitor = clickAwayMonitor { NSEvent.removeMonitor(monitor) }
        clickAwayMonitor = nil
    }
}
