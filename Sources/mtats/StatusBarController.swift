// Sources/mtats/StatusBarController.swift
// SPDX-License-Identifier: MIT
import AppKit
import SwiftUI
import MTatsPluginKit

public final class StatusBarController {
    private var items: [String: NSStatusItem] = [:]
    private var widgets: [MTatsWidget] = []
    /// Interval each widget was last started at; absent means stopped.
    private var runningIntervals: [String: TimeInterval] = [:]
    private var settingsItem: NSStatusItem?
    private var settingsWindow: NSWindow?
    private let settings: SettingsStore
    private let loader: PluginLoader

    public init(settings: SettingsStore, loader: PluginLoader) {
        self.settings = settings
        self.loader = loader
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
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            guard let button = item.button else { continue }
            let hosting = PassthroughHostingView(rootView: widget.menuBarView())
            button.addSubview(hosting)
            var width: CGFloat = 0
            let fit = { [weak item, weak button, weak hosting] in
                guard let item, let button, let hosting else { return }
                let grown = WidgetLifecycle.itemWidth(current: width, measured: hosting.fittingSize.width)
                if grown != width {
                    width = grown
                    item.length = grown
                }
                let target = NSRect(x: 0, y: 0, width: width, height: button.bounds.height > 0 ? button.bounds.height : NSStatusBar.system.thickness)
                if hosting.frame != target { hosting.frame = target }
            }
            hosting.onLayout = fit
            fit()

            let popover = NSPopover()
            let detail = NSHostingController(rootView: widget.detailView())
            // Let the popover take the detail view's size, so content isn't clipped and the
            // arrow sits over the status item instead of drifting to a fixed default size.
            detail.sizingOptions = [.preferredContentSize]
            popover.contentViewController = detail
            popover.behavior = .transient
            button.target = PopoverShower.shared
            button.action = #selector(PopoverShower.toggle(_:))
            PopoverShower.shared.register(button: button, popover: popover)

            items[widget.id] = item
            // Apply the public-IP toggle before start() — start() can fire an immediate
            // lookup, and doing that before the toggle is applied would ignore a user who
            // has it turned off (a privacy-relevant external call per spec §6).
            if let toggleable = widget as? PublicIPToggleable {
                toggleable.setPublicIPLookupEnabled(settings.publicIPLookupEnabled)
            }
            apply(to: widget)
        }

        if settingsItem == nil { presentSettingsMenuItem() }
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
    }

    private func apply(to widget: MTatsWidget) {
        let enabled = settings.isEnabled(widgetID: widget.id)
        items[widget.id]?.isVisible = enabled
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
        SettingsView(settings: settings, widgets: widgets, loader: loader, onToggle: { [weak self] in self?.applyEnabledState() })
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

    @objc private func openSettings() {
        if settingsWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 360, height: 280), styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = "mtats Settings"
            window.contentView = NSHostingView(rootView: makeSettingsView())
            window.isReleasedWhenClosed = false
            settingsWindow = window
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate()
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

/// Minimal shared target/action so each status item's button can toggle its own popover.
private final class PopoverShower: NSObject {
    static let shared = PopoverShower()
    private var popovers: [ObjectIdentifier: NSPopover] = [:]

    func register(button: NSStatusBarButton, popover: NSPopover) {
        popovers[ObjectIdentifier(button)] = popover
    }

    @objc func toggle(_ sender: NSStatusBarButton) {
        guard let popover = popovers[ObjectIdentifier(sender)] else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
        }
    }
}
