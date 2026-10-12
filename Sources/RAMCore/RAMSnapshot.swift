// SPDX-License-Identifier: MIT
import Foundation

public struct RAMSnapshot: Equatable {
    public let wiredBytes: UInt64
    public let activeBytes: UInt64
    public let inactiveBytes: UInt64
    public let compressedBytes: UInt64
    public let freeBytes: UInt64
    public let totalBytes: UInt64

    /// Approximates Activity Monitor's "Memory Used" (spec §5) rather than total - free:
    /// inactive/cached pages are reclaimable on demand, so counting them as "used" would read
    /// close to 100% on any Mac that's been running a while. Not an exact match — `active`
    /// still includes some file-backed pages Activity Monitor files under "Cached Files".
    public var usedFraction: Double {
        guard totalBytes > 0 else { return 0.0 }
        let used = min(wiredBytes + activeBytes + compressedBytes, totalBytes)
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
