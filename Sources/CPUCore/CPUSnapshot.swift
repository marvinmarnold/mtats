// SPDX-License-Identifier: MIT
import Foundation

public struct CPUSnapshot: Equatable {
    public let perCoreUsage: [Double]
    public let totalUsage: Double
    public let timestamp: Date

    public init(perCoreUsage: [Double], totalUsage: Double, timestamp: Date = Date()) {
        self.perCoreUsage = perCoreUsage
        self.totalUsage = totalUsage
        self.timestamp = timestamp
    }
}
