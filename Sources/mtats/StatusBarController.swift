// Sources/mtats/StatusBarController.swift
// SPDX-License-Identifier: MIT
import AppKit
import SwiftUI
import MTatsPluginKit

public final class StatusBarController {
    private var items: [String: NSStatusItem] = [:]
    private var widgets: [MTatsWidget] = []
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
        self.widgets.append(contentsOf: newWidgets)

        for widget in newWidgets {
            // NSStatusItem.squareLength reserves only ~24pt in the menu bar — not nearly
            // enough for "CPU 45%" or "↓1.2 MB/s ↑340 KB/s" at 11pt. .variableLength with an
            // explicit, generously-sized length (per widget, since Network's text runs much
            // longer than CPU/RAM/GPU's) is what actually reserves room for the content.
            let width: CGFloat = widget.id == "network" ? 150 : 70
            let item = NSStatusBar.system.statusItem(withLength: width)
            let hosting = PassthroughHostingView(rootView: widget.menuBarView())
            hosting.frame = NSRect(x: 0, y: 0, width: width, height: NSStatusItem.squareLength)
            hosting.autoresizingMask = [.width, .height]
            item.button?.addSubview(hosting)

            let popover = NSPopover()
            popover.contentViewController = NSHostingController(rootView: widget.detailView())
            popover.behavior = .transient
            item.button?.target = PopoverShower.shared
            item.button?.action = #selector(PopoverShower.toggle(_:))
            PopoverShower.shared.register(button: item.button!, popover: popover)

            items[widget.id] = item
            let enabled = settings.isEnabled(widgetID: widget.id)
            item.isVisible = enabled
            // Apply the public-IP toggle before start() — start() can fire an immediate
            // lookup, and doing that before the toggle is applied would ignore a user who
            // has it turned off (a privacy-relevant external call per spec §6).
            if let toggleable = widget as? PublicIPToggleable {
                toggleable.setPublicIPLookupEnabled(settings.publicIPLookupEnabled)
            }
            if enabled {
                widget.start(interval: settings.refreshInterval)
            }
        }

        if settingsItem == nil { presentSettingsMenuItem() }
    }

    /// spec §6: disabling a Widget must make it disappear from the menu bar, not just stop
    /// updating — a frozen, stale item left behind looks like a bug, not a disabled feature.
    public func applyEnabledState() {
        for widget in widgets {
            let enabled = settings.isEnabled(widgetID: widget.id)
            items[widget.id]?.isVisible = enabled
            if let toggleable = widget as? PublicIPToggleable {
                toggleable.setPublicIPLookupEnabled(settings.publicIPLookupEnabled)
            }
            if enabled {
                widget.start(interval: settings.refreshInterval)
            } else {
                widget.stop()
            }
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

    @objc private func openSettings() {
        if settingsWindow == nil {
            let view = SettingsView(settings: settings, widgets: widgets, loader: loader, onToggle: { [weak self] in self?.applyEnabledState() })
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 360, height: 280), styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = "mtats Settings"
            window.contentView = NSHostingView(rootView: view)
            window.isReleasedWhenClosed = false
            settingsWindow = window
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

/// NSView's default hit-testing claims any click inside its bounds, including a plain
/// non-interactive SwiftUI Text — which would swallow clicks meant for the NSStatusBarButton
/// hosting it (the popover toggle would never fire). Returning nil lets the click pass through.
private final class PassthroughHostingView<Content: View>: NSHostingView<Content> {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
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
