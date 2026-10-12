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
