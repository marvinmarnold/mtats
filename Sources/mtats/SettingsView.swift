// Sources/mtats/SettingsView.swift
// SPDX-License-Identifier: MIT
import AppKit
import SwiftUI
import MTatsPluginKit

public struct SettingsView: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var loader: PluginLoader
    let widgets: [MTatsWidget]
    let updateControls: UpdateControls?
    let onToggle: () -> Void

    public init(settings: SettingsStore, widgets: [MTatsWidget], loader: PluginLoader, updateControls: UpdateControls? = nil, onToggle: @escaping () -> Void) {
        self.settings = settings
        self.widgets = widgets
        self.loader = loader
        self.updateControls = updateControls
        self.onToggle = onToggle
    }

    public var body: some View {
        TabView {
            settingsForm.tabItem { Text("Settings") }
            DiagnosticsView(loader: loader).tabItem { Text("Diagnostics") }
        }.padding()
    }

    private var settingsForm: some View {
        Form {
            ForEach(widgets, id: \.id) { widget in
                Toggle(widget.displayName, isOn: Binding(
                    get: { settings.isEnabled(widgetID: widget.id) },
                    set: { settings.setEnabled($0, widgetID: widget.id); onToggle() }
                ))
            }
            Stepper(value: Binding(
                get: { settings.refreshInterval },
                set: { settings.refreshInterval = $0; onToggle() }
            ), in: 0.5...5.0, step: 0.5) {
                Text(String(format: "Refresh every %.1fs", settings.refreshInterval))
            }
            Toggle("Launch at login", isOn: Binding(
                get: { settings.launchAtLoginEnabled },
                set: { settings.launchAtLoginEnabled = $0 }
            ))
            Toggle("Look up public IP", isOn: Binding(
                get: { settings.publicIPLookupEnabled },
                set: { settings.publicIPLookupEnabled = $0; onToggle() }
            ))
            if let updateControls {
                UpdatesSection(controls: updateControls)
            }
            // mtats is LSUIElement (no Dock icon, no app menu) — this is the only menu-bar
            // utility's usual way to quit that a user has, short of Activity Monitor.
            Button("Quit mtats") { NSApp.terminate(nil) }
        }.padding()
    }
}

/// spec §4.2: a plugin the Host skipped (bad signature, API-version mismatch) gets "a visible
/// reason in a diagnostics view" — this is that view, reading PluginLoader's published log.
public struct DiagnosticsView: View {
    @ObservedObject var loader: PluginLoader

    public init(loader: PluginLoader) {
        self.loader = loader
    }

    public var body: some View {
        VStack(alignment: .leading) {
            if loader.diagnosticMessages.isEmpty {
                Text("No issues — every plugin found loaded successfully.")
                    .foregroundStyle(.secondary)
            } else {
                List(loader.diagnosticMessages, id: \.self) { message in
                    Text(message)
                }
            }
        }.padding()
    }
}

private struct UpdatesSection: View {
    @ObservedObject var controls: UpdateControls
    var body: some View {
        Button("Check for Updates…") { controls.checkForUpdates() }
            .disabled(!controls.canCheckForUpdates)
        Toggle("Automatically check for updates", isOn: Binding(
            get: { controls.automaticallyChecks },
            set: { controls.automaticallyChecks = $0 }
        ))
        let info = Bundle.main.infoDictionary
        Text("Version \(info?["CFBundleShortVersionString"] as? String ?? "?") (\(info?["CFBundleVersion"] as? String ?? "?"))")
            .foregroundStyle(.secondary)
    }
}
