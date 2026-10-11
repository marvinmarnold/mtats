// SPDX-License-Identifier: MIT
import SwiftUI

/// Crosses the Plugin<->Host seam. No associated types (ADR-0005): a dynamically loaded
/// plugin and the Host must agree on this exact, non-generic shape.
public protocol MTatsWidget: AnyObject {
    var id: String { get }
    var displayName: String { get }

    /// Begin producing data at the given cadence (spec §6: one Host-wide setting, passed
    /// in rather than hardcoded, so Plugins never need to know about Host settings types).
    /// Safe to call again with a different interval even without calling stop() first —
    /// implementations must restart cleanly (see each *MetricsSource.start(), which always
    /// calls its own stop() internally before reconfiguring).
    func start(interval: TimeInterval)

    /// Stop producing data and release resources. Safe to call even if start() was never called.
    func stop()

    /// Live menu-bar presentation. Must update reactively as new data arrives.
    func menuBarView() -> AnyView

    /// Dropdown detail presentation.
    func detailView() -> AnyView
}

/// A Plugin's entry point. The concrete implementing class MUST subclass NSObject and be
/// named via `@objc(ExactName)` matching the plugin bundle's Info.plist NSPrincipalClass key —
/// that's how Bundle.principalClass finds it at runtime (ADR-0001, ADR-0005).
public protocol PluginEntry: AnyObject {
    static func makeWidgets() -> [MTatsWidget]
}

/// Every Plugin bundle must declare this exact integer in its Info.plist under
/// MTatsPluginAPIVersion. The Host rejects any mismatch (ADR-0004).
public let pluginAPIVersion: Int = 1

/// Optional, narrow extension a MTatsWidget can additionally conform to. Kept separate from
/// `MTatsWidget` itself so the one widget that needs it (Network, for the public-IP toggle —
/// spec §6) doesn't force every other widget to carry an irrelevant requirement.
public protocol PublicIPToggleable: AnyObject {
    func setPublicIPLookupEnabled(_ enabled: Bool)
}
