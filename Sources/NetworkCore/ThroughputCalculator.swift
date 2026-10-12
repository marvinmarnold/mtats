// SPDX-License-Identifier: MIT
import Foundation

public struct ThroughputCalculator {
    public static func throughput(
        previous: [InterfaceCounters],
        current: [InterfaceCounters],
        elapsed: TimeInterval
    ) -> (rxBytesPerSec: Double, txBytesPerSec: Double, perInterface: [String: (rx: Double, tx: Double)]) {
        guard elapsed > 0 else { return (0, 0, [:]) }

        let previousByName = Dictionary(uniqueKeysWithValues: previous.map { ($0.name, $0) })
        var perInterface: [String: (rx: Double, tx: Double)] = [:]
        var totalRx: Double = 0
        var totalTx: Double = 0

        for cur in current {
            guard let prev = previousByName[cur.name] else { continue } // new interface, no baseline yet
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
