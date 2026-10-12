// Tests/CPUCoreTests/CPUCalculatorTests.swift
// SPDX-License-Identifier: MIT
import XCTest
@testable import CPUCore
import Darwin

final class CPUCalculatorTests: XCTestCase {
    private func assertEqual(_ actual: [Double], _ expected: [Double], accuracy: Double, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(actual.count, expected.count, file: file, line: line)
        for (a, e) in zip(actual, expected) {
            XCTAssertEqual(a, e, accuracy: accuracy, file: file, line: line)
        }
    }

    private func load(user: UInt32, system: UInt32, idle: UInt32, nice: UInt32) -> host_cpu_load_info {
        var info = host_cpu_load_info()
        info.cpu_ticks.0 = user
        info.cpu_ticks.1 = system
        info.cpu_ticks.2 = idle
        info.cpu_ticks.3 = nice
        return info
    }

    func test_fullyIdleCore_reportsZeroUsage() {
        let previous = [load(user: 0, system: 0, idle: 1000, nice: 0)]
        let current = [load(user: 0, system: 0, idle: 2000, nice: 0)]
        let snapshot = CPUCalculator.usage(previous: previous, current: current)
        assertEqual(snapshot.perCoreUsage, [0.0], accuracy: 0.001)
        XCTAssertEqual(snapshot.totalUsage, 0.0, accuracy: 0.001)
    }

    func test_fullyBusyCore_reportsFullUsage() {
        let previous = [load(user: 1000, system: 0, idle: 0, nice: 0)]
        let current = [load(user: 2000, system: 0, idle: 0, nice: 0)]
        let snapshot = CPUCalculator.usage(previous: previous, current: current)
        assertEqual(snapshot.perCoreUsage, [1.0], accuracy: 0.001)
    }

    func test_twoCoresAtDifferentLoads_averagesForTotal() {
        let previous = [load(user: 0, system: 0, idle: 0, nice: 0), load(user: 0, system: 0, idle: 0, nice: 0)]
        let current = [load(user: 1000, system: 0, idle: 0, nice: 0), load(user: 0, system: 0, idle: 1000, nice: 0)]
        let snapshot = CPUCalculator.usage(previous: previous, current: current)
        assertEqual(snapshot.perCoreUsage, [1.0, 0.0], accuracy: 0.001)
        XCTAssertEqual(snapshot.totalUsage, 0.5, accuracy: 0.001)
    }

    func test_counterWentBackwards_treatedAsZeroNotNegative() {
        // Review Focus analog for CPU: a tick counter must never produce negative usage.
        let previous = [load(user: 5000, system: 0, idle: 0, nice: 0)]
        let current = [load(user: 1000, system: 0, idle: 0, nice: 0)] // reset/overflow
        let snapshot = CPUCalculator.usage(previous: previous, current: current)
        assertEqual(snapshot.perCoreUsage, [0.0], accuracy: 0.001)
    }
}
