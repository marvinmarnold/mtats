// Sources/mtats/SettingsStore.swift
// SPDX-License-Identifier: MIT
import Foundation
import ServiceManagement

public final class SettingsStore: ObservableObject {
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func isEnabled(widgetID: String) -> Bool {
        defaults.object(forKey: "widget.\(widgetID).enabled") as? Bool ?? true
    }

    public func setEnabled(_ enabled: Bool, widgetID: String) {
        objectWillChange.send()
        defaults.set(enabled, forKey: "widget.\(widgetID).enabled")
    }

    public var refreshInterval: TimeInterval {
        get { let value = defaults.double(forKey: "refreshInterval"); return value > 0 ? value : 1.0 }
        set {
            objectWillChange.send()
            defaults.set(newValue, forKey: "refreshInterval")
        }
    }

    /// Actually registers/unregisters with the system (ServiceManagement), not just a
    /// stored preference — spec §6 lists this as a real toggle, not a label.
    public var launchAtLoginEnabled: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            objectWillChange.send()
            do {
                if newValue { try SMAppService.mainApp.register() }
                else { try SMAppService.mainApp.unregister() }
            } catch {
                print("SettingsStore: launch-at-login change failed: \(error)")
            }
        }
    }

    public var publicIPLookupEnabled: Bool {
        get { defaults.object(forKey: "publicIPLookupEnabled") as? Bool ?? true }
        set {
            objectWillChange.send()
            defaults.set(newValue, forKey: "publicIPLookupEnabled")
        }
    }
}
