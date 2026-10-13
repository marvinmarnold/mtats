// SPDX-License-Identifier: MIT
import Darwin

public struct RAMCalculator {
    public static func snapshot(stats: vm_statistics64, pageSize: UInt64, totalPhysicalBytes: UInt64) -> RAMSnapshot {
        RAMSnapshot(
            wiredBytes: UInt64(stats.wire_count) * pageSize,
            activeBytes: UInt64(stats.active_count) * pageSize,
            inactiveBytes: UInt64(stats.inactive_count) * pageSize,
            compressedBytes: UInt64(stats.compressor_page_count) * pageSize,
            freeBytes: UInt64(stats.free_count) * pageSize,
            totalBytes: totalPhysicalBytes
        )
    }
}
