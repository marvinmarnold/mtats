// SPDX-License-Identifier: MIT
import XCTest
@testable import NetworkCore

final class RateFormatTests: XCTestCase {
    func test_unitsScaleWithMagnitude() {
        XCTAssertTrue(RateFormat.string(500).contains("B/s"))
        XCTAssertTrue(RateFormat.string(5_000).contains("KB/s"))
        XCTAssertTrue(RateFormat.string(5_000_000).contains("MB/s"))
    }

    // The menu-bar item resizes when its text width changes, which made the network widget
    // jump around. Every rate must render to the same number of characters.
    func test_outputWidthIsStableAcrossMagnitudes() {
        let lengths = [0.0, 42, 1_500, 987_654, 12_345_678, 3_000_000_000].map { RateFormat.string($0).count }
        XCTAssertEqual(Set(lengths).count, 1, "lengths were \(lengths)")
    }
}
