// Tests/GPUCoreTests/GPUCalculatorTests.swift
// SPDX-License-Identifier: MIT
import AppKit
import SwiftUI
import XCTest
@testable import GPUCore

final class GPUCalculatorTests: XCTestCase {
    func test_extractsDeviceUtilizationPercent() {
        let dict: [String: Any] = ["Device Utilization %": 42]
        guard let utilization = GPUCalculator.utilization(fromPerformanceStatistics: dict) else {
            return XCTFail("expected non-nil utilization")
        }
        XCTAssertEqual(utilization, 0.42, accuracy: 0.001)
    }

    func test_missingKey_returnsNilNotCrashing() {
        // Review Focus: undocumented IOKit keys can disappear on a macOS update.
        let dict: [String: Any] = ["Something Else": 1]
        XCTAssertNil(GPUCalculator.utilization(fromPerformanceStatistics: dict))
    }

    func test_wrongValueType_returnsNilNotCrashing() {
        let dict: [String: Any] = ["Device Utilization %": "not a number"]
        XCTAssertNil(GPUCalculator.utilization(fromPerformanceStatistics: dict))
    }

    // Undocumented IOKit values can be out of range across driver versions; the menu bar must
    // never show "GPU 150%" or a negative number.
    func test_outOfRangeValues_areClampedToZeroThroughOne() {
        XCTAssertEqual(GPUCalculator.utilization(fromPerformanceStatistics: ["Device Utilization %": 150]), 1.0)
        XCTAssertEqual(GPUCalculator.utilization(fromPerformanceStatistics: ["Device Utilization %": -5]), 0.0)
    }

    func test_emptyDictionary_returnsNil() {
        XCTAssertNil(GPUCalculator.utilization(fromPerformanceStatistics: [:]))
    }
}

final class GPUIconTests: XCTestCase {
    /// SF Symbols has no graphics-card glyph, so the GPU icon is drawn; it must actually paint pixels.
    @MainActor func test_gpuGlyph_rendersVisiblePixels() throws {
        let renderer = ImageRenderer(content: GPUGlyph().frame(width: 32, height: 32).foregroundStyle(.black))
        renderer.scale = 2
        let cg = try XCTUnwrap(renderer.cgImage)
        let data = try XCTUnwrap(cg.dataProvider?.data as Data?)
        XCTAssertTrue(data.contains { $0 != 0 }, "glyph rendered fully transparent")
    }
}
