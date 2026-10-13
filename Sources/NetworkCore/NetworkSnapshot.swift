// SPDX-License-Identifier: MIT
import Foundation

public struct InterfaceCounters: Equatable {
    public let name: String
    public let rxBytes: UInt64
    public let txBytes: UInt64
    public init(name: String, rxBytes: UInt64, txBytes: UInt64) {
        self.name = name; self.rxBytes = rxBytes; self.txBytes = txBytes
    }
}

public struct NetworkSnapshot: Equatable {
    public let rxBytesPerSec: Double
    public let txBytesPerSec: Double
    public let perInterface: [String: Double] // combined rx+tx, for the detail view
    public let localIPv4: String?
    public let publicIP: String?
    public let timestamp: Date
    public init(rxBytesPerSec: Double, txBytesPerSec: Double, perInterface: [String: Double], localIPv4: String?, publicIP: String?, timestamp: Date = Date()) {
        self.rxBytesPerSec = rxBytesPerSec; self.txBytesPerSec = txBytesPerSec
        self.perInterface = perInterface; self.localIPv4 = localIPv4; self.publicIP = publicIP
        self.timestamp = timestamp
    }
}
