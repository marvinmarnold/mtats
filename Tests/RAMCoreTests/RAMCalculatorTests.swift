// Tests/RAMCoreTests/RAMCalculatorTests.swift
import XCTest
@testable import RAMCore
import Darwin

final class RAMCalculatorTests: XCTestCase {
    func test_knownPageCounts_convertToExpectedByteValuesAndFraction() {
        var stats = vm_statistics64()
        stats.wire_count = 100          // 100 pages wired
        stats.active_count = 200
        stats.inactive_count = 50
        stats.compressor_page_count = 25
        stats.free_count = 25
        let pageSize: UInt64 = 4096
        let totalPhysical: UInt64 = 400 * 4096 // exactly matches the pages above

        let snapshot = RAMCalculator.snapshot(stats: stats, pageSize: pageSize, totalPhysicalBytes: totalPhysical)

        XCTAssertEqual(snapshot.wiredBytes, 100 * 4096)
        XCTAssertEqual(snapshot.activeBytes, 200 * 4096)
        XCTAssertEqual(snapshot.inactiveBytes, 50 * 4096)
        XCTAssertEqual(snapshot.compressedBytes, 25 * 4096)
        XCTAssertEqual(snapshot.freeBytes, 25 * 4096)
        XCTAssertEqual(snapshot.totalBytes, totalPhysical)
        // used = total - free = 375/400
        XCTAssertEqual(snapshot.usedFraction, 375.0 / 400.0, accuracy: 0.0001)
    }

    func test_zeroTotalBytes_doesNotDivideByZero() {
        let snapshot = RAMCalculator.snapshot(stats: vm_statistics64(), pageSize: 4096, totalPhysicalBytes: 0)
        XCTAssertEqual(snapshot.usedFraction, 0.0)
    }
}
