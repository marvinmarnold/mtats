// SPDX-License-Identifier: MIT
import XCTest
@testable import mtats

final class StatusItemIdentityTests: XCTestCase {
    // Named items keep their position/visibility across relaunches and display changes;
    // anonymous "Item-N" identities don't.
    func test_names_areStableAndPerRole() {
        XCTAssertEqual(StatusItemNames.widget("cpu"), "mtats.widget.cpu")
        XCTAssertEqual(StatusItemNames.compact, "mtats.compact")
        XCTAssertEqual(StatusItemNames.settings, "mtats.settings")
    }

    func test_legacyKeys_areOnlyTheAnonymousItemNKeys() {
        let keys = [
            "NSStatusItem Preferred Position Item-0",
            "NSStatusItem VisibleCC Item-5",
            "NSStatusItem Visible Item-12",
            "NSStatusItem Preferred Position mtats.compact",
            "NSStatusItem VisibleCC mtats.widget.cpu",
            "widget.cpu.enabled",
            "compactMenuBar",
        ]
        XCTAssertEqual(Set(StatusItemMigration.legacyKeys(in: keys)),
                       ["NSStatusItem Preferred Position Item-0", "NSStatusItem VisibleCC Item-5", "NSStatusItem Visible Item-12"])
    }

    func test_migration_removesLegacyKeysOnce_andKeepsEverythingElse() {
        let defaults = UserDefaults(suiteName: "mtats.tests.\(UUID())")!
        defaults.set(false, forKey: "NSStatusItem VisibleCC Item-3")
        defaults.set(120.0, forKey: "NSStatusItem Preferred Position mtats.compact")
        defaults.set(true, forKey: "compactMenuBar")
        StatusItemMigration.run(defaults: defaults)
        XCTAssertNil(defaults.object(forKey: "NSStatusItem VisibleCC Item-3"))
        XCTAssertNotNil(defaults.object(forKey: "NSStatusItem Preferred Position mtats.compact"))
        XCTAssertTrue(defaults.bool(forKey: "compactMenuBar"))
        // Second run is a no-op: a later anonymous key (should one ever appear) is left alone.
        defaults.set(false, forKey: "NSStatusItem VisibleCC Item-9")
        StatusItemMigration.run(defaults: defaults)
        XCTAssertNotNil(defaults.object(forKey: "NSStatusItem VisibleCC Item-9"))
    }
}

final class DisplaySettleTests: XCTestCase {
    func test_notSettled_untilQuietPeriodPasses() {
        var settle = DisplaySettle(quietPeriod: 4)
        let t0 = Date(timeIntervalSince1970: 1000)
        XCTAssertTrue(settle.isSettled(now: t0), "no change seen yet")
        settle.noteChange(at: t0)
        XCTAssertFalse(settle.isSettled(now: t0.addingTimeInterval(3.9)))
        XCTAssertTrue(settle.isSettled(now: t0.addingTimeInterval(4.0)))
    }

    func test_anotherChange_restartsTheQuietPeriod() {
        var settle = DisplaySettle(quietPeriod: 4)
        let t0 = Date(timeIntervalSince1970: 1000)
        settle.noteChange(at: t0)
        settle.noteChange(at: t0.addingTimeInterval(3))
        XCTAssertFalse(settle.isSettled(now: t0.addingTimeInterval(6)))
        XCTAssertTrue(settle.isSettled(now: t0.addingTimeInterval(7)))
    }

    // Display reconfiguration moves item windows around; a single odd reading must never collapse the bar.
    func test_debounce_needsThreeConsecutiveHiddenReadings() {
        var debounce = HiddenDebounce()
        XCTAssertFalse(debounce.record(hidden: true))
        XCTAssertFalse(debounce.record(hidden: true))
        XCTAssertTrue(debounce.record(hidden: true))
    }
}
