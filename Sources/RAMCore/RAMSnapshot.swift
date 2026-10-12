// SPDX-License-Identifier: MIT
import Foundation

public struct RAMSnapshot: Equatable {
    public let wiredBytes: UInt64
    public let activeBytes: UInt64
    public let inactiveBytes: UInt64
    public let compressedBytes: UInt64
    public let freeBytes: UInt64
    public let totalBytes: UInt64

    public var usedFraction: Double {
        guard totalBytes > 0 else { return 0.0 }
        let used = totalBytes > freeBytes ? totalBytes - freeBytes : 0
        return Double(used) / Double(totalBytes)
    }

    public init(wiredBytes: UInt64, activeBytes: UInt64, inactiveBytes: UInt64, compressedBytes: UInt64, freeBytes: UInt64, totalBytes: UInt64) {
        self.wiredBytes = wiredBytes
        self.activeBytes = activeBytes
        self.inactiveBytes = inactiveBytes
        self.compressedBytes = compressedBytes
        self.freeBytes = freeBytes
        self.totalBytes = totalBytes
    }
}
