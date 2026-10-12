// Sources/mtats/SettingsView.swift
// SPDX-License-Identifier: MIT
import SwiftUI
import MTatsPluginKit

public struct SettingsView: View {
    @ObservedObject var settings: SettingsStore
    let widgets: [MTatsWidget]
    let onToggle: () -> Void

    public init(settings: SettingsStore, widgets: [MTatsWidget], onToggle: @escaping () -> Void) {
        self.settings = settings
        self.widgets = widgets
        self.onToggle = onToggle
    }

    public var body: some View {
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
        }.padding()
    }
}
