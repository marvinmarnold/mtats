// SPDX-License-Identifier: MIT
import Darwin

public struct CPUCalculator {
    public static func usage(previous: [host_cpu_load_info], current: [host_cpu_load_info]) -> CPUSnapshot {
        let count = min(previous.count, current.count)
        var perCore: [Double] = []
        perCore.reserveCapacity(count)

        for i in 0..<count {
            let p = previous[i].cpu_ticks
            let c = current[i].cpu_ticks
            let userDelta = delta(c.0, p.0)
            let systemDelta = delta(c.1, p.1)
            let idleDelta = delta(c.2, p.2)
            let niceDelta = delta(c.3, p.3)
            let total = userDelta + systemDelta + idleDelta + niceDelta
            perCore.append(total == 0 ? 0.0 : Double(total - idleDelta) / Double(total))
        }

        let totalUsage = perCore.isEmpty ? 0.0 : perCore.reduce(0, +) / Double(perCore.count)
        return CPUSnapshot(perCoreUsage: perCore, totalUsage: totalUsage)
    }

    /// Counters only ever increase in a healthy sample pair. A decrease means the counter
    /// reset (CPU went offline/online, overflow) — treat that tick's contribution as zero
    /// rather than letting it go negative (Review Focus: counters must never go negative).
    private static func delta(_ current: UInt32, _ previous: UInt32) -> UInt32 {
        current >= previous ? current - previous : 0
    }
}
