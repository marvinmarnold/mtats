// SPDX-License-Identifier: MIT
import Foundation

public struct GPUCalculator {
    public static func utilization(fromPerformanceStatistics dict: [String: Any]) -> Double? {
        guard let raw = dict["Device Utilization %"] else { return nil }
        guard let number = raw as? NSNumber else { return nil }
        return number.doubleValue / 100.0
    }
}
