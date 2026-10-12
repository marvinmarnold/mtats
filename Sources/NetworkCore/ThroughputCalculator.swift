// SPDX-License-Identifier: MIT
import Foundation

public struct ThroughputCalculator {
    public static func throughput(
        previous: [InterfaceCounters],
        current: [InterfaceCounters],
        elapsed: TimeInterval
    ) -> (rxBytesPerSec: Double, txBytesPerSec: Double, perInterface: [String: (rx: Double, tx: Double)]) {
        guard elapsed > 0 else { return (0, 0, [:]) }

        let previousByName = Dictionary(previous.map { ($0.name, $0) }, uniquingKeysWith: { _, last in last })
        var perInterface: [String: (rx: Double, tx: Double)] = [:]
        var totalRx: Double = 0
        var totalTx: Double = 0

        for cur in current {
            guard let prev = previousByName[cur.name] else { continue } // new interface, no baseline yet
            // Known limitation: counters come from getifaddrs' `if_data`, which is 32-bit and
            // wraps at 4 GiB cumulative. A wrap looks identical to an interface reset, so it
            // reads as 0 for one sample during sustained high-throughput transfers. Do NOT
            // "fix" this by treating every decrease as a wrap — a genuine reset would then read
            // as a ~4 GiB spike. The real fix is 64-bit counters via sysctl NET_RT_IFLIST2 /
            // `if_data64` in IPAddressParser.
            let rxDelta = cur.rxBytes >= prev.rxBytes ? cur.rxBytes - prev.rxBytes : 0
            let txDelta = cur.txBytes >= prev.txBytes ? cur.txBytes - prev.txBytes : 0
            let rxRate = Double(rxDelta) / elapsed
            let txRate = Double(txDelta) / elapsed
            perInterface[cur.name] = (rx: rxRate, tx: txRate)
            totalRx += rxRate
            totalTx += txRate
        }

        return (totalRx, totalTx, perInterface)
    }
}
