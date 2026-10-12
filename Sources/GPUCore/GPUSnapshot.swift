// SPDX-License-Identifier: MIT
import Foundation

public struct GPUSnapshot: Equatable {
    public let utilization: Double? // nil means "N/A" — never show a fabricated number
    public let timestamp: Date
    public init(utilization: Double?, timestamp: Date = Date()) {
        self.utilization = utilization
        self.timestamp = timestamp
    }
}
