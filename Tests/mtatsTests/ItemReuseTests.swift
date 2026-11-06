// SPDX-License-Identifier: MIT
import XCTest
import SwiftUI
import MTatsPluginKit
@testable import mtats

private final class StubWidget: MTatsWidget {
    let id: String
    var displayName: String { id }
    init(_ id: String) { self.id = id }
    func start(interval: TimeInterval) {}
    func stop() {}
    func menuBarView() -> AnyView { AnyView(Text("12%").frame(width: 40)) }
    func detailView() -> AnyView { AnyView(Text("detail")) }
}

final class ItemReuseTests: XCTestCase {
    // Removing and recreating status items strands them at the far left (or nowhere) after display
    // changes; switching layouts must only show/hide the items that already exist.
    func test_switchingLayouts_reusesExistingStatusItems() {
        _ = NSApplication.shared
        let defaults = UserDefaults(suiteName: "mtats.tests.\(UUID())")!
        let settings = SettingsStore(defaults: defaults)
        let controller = StatusBarController(settings: settings, loader: PluginLoader(defaults: defaults))
        controller.present(widgets: [StubWidget("a"), StubWidget("b")])
        let normal = controller.statusItemIdentities

        settings.compactMenuBar = true; controller.applyEnabledState()
        let compact = controller.statusItemIdentities
        XCTAssertTrue(normal.isSubset(of: compact), "no item may be replaced when entering compact")

        settings.compactMenuBar = false; controller.applyEnabledState()
        settings.compactMenuBar = true; controller.applyEnabledState()
        settings.compactMenuBar = false; controller.applyEnabledState()
        XCTAssertEqual(controller.statusItemIdentities, compact, "repeated switching must not create or drop items")
    }

    func test_startingInCompact_neverCreatesSeparateItems() {
        _ = NSApplication.shared
        let defaults = UserDefaults(suiteName: "mtats.tests.\(UUID())")!
        let settings = SettingsStore(defaults: defaults)
        settings.compactMenuBar = true
        let controller = StatusBarController(settings: settings, loader: PluginLoader(defaults: defaults))
        controller.present(widgets: [StubWidget("a"), StubWidget("b")])
        // compact item + gear only
        XCTAssertEqual(controller.statusItemIdentities.count, 2)
    }
}
