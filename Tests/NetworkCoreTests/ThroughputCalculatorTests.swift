// Tests/NetworkCoreTests/ThroughputCalculatorTests.swift
// SPDX-License-Identifier: MIT
import XCTest
@testable import NetworkCore

final class ThroughputCalculatorTests: XCTestCase {
    func test_byteDeltaOverTime_computesBytesPerSecond() {
        let previous = [InterfaceCounters(name: "en0", rxBytes: 1000, txBytes: 500)]
        let current = [InterfaceCounters(name: "en0", rxBytes: 3000, txBytes: 1500)]
        let result = ThroughputCalculator.throughput(previous: previous, current: current, elapsed: 2.0)
        XCTAssertEqual(result.rxBytesPerSec, 1000, accuracy: 0.001) // (3000-1000)/2
        XCTAssertEqual(result.txBytesPerSec, 500, accuracy: 0.001)
        if let rx = result.perInterface["en0"]?.rx {
            XCTAssertEqual(rx, 1000, accuracy: 0.001)
        } else {
            XCTFail("missing en0 in perInterface")
        }
    }

    func test_interfaceCounterReset_isSkippedNotNegative() {
        // Review Focus: an interface going down/up (Wi-Fi toggle, sleep/wake) can reset its
        // counters. A decrease must never produce negative throughput.
        let previous = [InterfaceCounters(name: "en0", rxBytes: 50_000, txBytes: 10_000)]
        let current = [InterfaceCounters(name: "en0", rxBytes: 200, txBytes: 100)]
        let result = ThroughputCalculator.throughput(previous: previous, current: current, elapsed: 1.0)
        XCTAssertEqual(result.rxBytesPerSec, 0, accuracy: 0.001)
        XCTAssertEqual(result.txBytesPerSec, 0, accuracy: 0.001)
    }

    func test_interfaceDisappearsBetweenSamples_isIgnoredNotCrashing() {
        let previous = [InterfaceCounters(name: "en0", rxBytes: 100, txBytes: 100),
                         InterfaceCounters(name: "utun0", rxBytes: 100, txBytes: 100)]
        let current = [InterfaceCounters(name: "en0", rxBytes: 200, txBytes: 200)] // utun0 gone
        let result = ThroughputCalculator.throughput(previous: previous, current: current, elapsed: 1.0)
        XCTAssertEqual(result.perInterface.count, 1)
        XCTAssertNil(result.perInterface["utun0"])
    }

    // ThroughputCalculator is public API; a caller handing it two counters with the same
    // interface name must not crash the Host.
    func test_duplicateInterfaceNamesInPrevious_doNotTrap() {
        let previous = [InterfaceCounters(name: "en0", rxBytes: 100, txBytes: 100),
                        InterfaceCounters(name: "en0", rxBytes: 150, txBytes: 150)]
        let current = [InterfaceCounters(name: "en0", rxBytes: 200, txBytes: 200)]
        let result = ThroughputCalculator.throughput(previous: previous, current: current, elapsed: 1.0)
        XCTAssertEqual(result.perInterface.count, 1)
    }

    func test_zeroElapsed_doesNotDivideByZero() {
        let previous = [InterfaceCounters(name: "en0", rxBytes: 100, txBytes: 100)]
        let current = [InterfaceCounters(name: "en0", rxBytes: 200, txBytes: 200)]
        let result = ThroughputCalculator.throughput(previous: previous, current: current, elapsed: 0)
        XCTAssertEqual(result.rxBytesPerSec, 0)
    }
}
