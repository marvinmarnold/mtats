// SPDX-License-Identifier: MIT
import XCTest
@testable import mtats

final class WidgetLifecycleTests: XCTestCase {
    func test_disabledAndNotRunning_doesNothing() {
        XCTAssertEqual(WidgetLifecycle.action(runningInterval: nil, enabled: false, interval: 1), .none)
    }

    func test_disabledButRunning_stops() {
        XCTAssertEqual(WidgetLifecycle.action(runningInterval: 1, enabled: false, interval: 1), .stop)
    }

    func test_enabledAndNotRunning_starts() {
        XCTAssertEqual(WidgetLifecycle.action(runningInterval: nil, enabled: true, interval: 2), .start(2))
    }

    // Toggling an unrelated widget or the public-IP setting must not restart a widget that's
    // already running at the right interval — a restart wipes its sampling baseline and, for
    // Network, fires an external public-IP request.
    func test_enabledAndAlreadyRunningAtSameInterval_doesNothing() {
        XCTAssertEqual(WidgetLifecycle.action(runningInterval: 1, enabled: true, interval: 1), .none)
    }

    func test_enabledAndRunningAtDifferentInterval_restartsAtNewInterval() {
        XCTAssertEqual(WidgetLifecycle.action(runningInterval: 1, enabled: true, interval: 2.5), .start(2.5))
    }

    func test_itemWidth_growsToFitMeasuredContent() {
        XCTAssertEqual(WidgetLifecycle.itemWidth(current: 40, measured: 60), 68)
    }

    // Shrinking as digits change ("CPU 100%" → "CPU 5%") would make every item to its left
    // shift sideways every second.
    func test_itemWidth_neverShrinks() {
        XCTAssertEqual(WidgetLifecycle.itemWidth(current: 90, measured: 30), 90)
    }
}

final class SettingsPlacementTests: XCTestCase {
    private let visible = CGRect(x: 0, y: 78, width: 1452, height: 688) // below the menu bar, bottom-origin

    func testHangsJustBelowTheAnchorCenteredOnIt() {
        let anchor = CGRect(x: 700, y: 766, width: 24, height: 30) // status item window, top of screen
        let origin = SettingsPlacement.origin(size: CGSize(width: 360, height: 280), below: anchor, in: visible)
        XCTAssertEqual(origin.x, 700 + 12 - 180)
        XCTAssertEqual(origin.y, 766 - 4 - 280) // 4pt gap under the menu bar, not screen-centered
    }

    func testClampsToTheRightEdgeWhenAnchorIsNearIt() {
        let anchor = CGRect(x: 1430, y: 766, width: 24, height: 30)
        let origin = SettingsPlacement.origin(size: CGSize(width: 360, height: 280), below: anchor, in: visible)
        XCTAssertEqual(origin.x, 1452 - 360)
    }
}
