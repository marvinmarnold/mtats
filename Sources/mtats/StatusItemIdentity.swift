// Sources/mtats/StatusItemIdentity.swift
// SPDX-License-Identifier: MIT
import Foundation

/// Stable `autosaveName`s. macOS keys a status item's saved position and visibility on this name;
/// without one it falls back to an anonymous "Item-N" that changes whenever items are created in a
/// different order, which strands items in the wrong place (or nowhere) after relaunches and
/// display changes.
public enum StatusItemNames {
    public static let compact = "mtats.compact"
    public static let settings = "mtats.settings"
    public static func widget(_ id: String) -> String { "mtats.widget.\(id)" }
}

/// Earlier builds created anonymous items, leaving "NSStatusItem … Item-N" keys (some marking an
/// item hidden) in our defaults. Clear them once so a stale flag can't hide a freshly named item.
public enum StatusItemMigration {
    static let doneKey = "statusItemNamesMigrated"

    public static func legacyKeys(in keys: [String]) -> [String] {
        keys.filter { $0.hasPrefix("NSStatusItem ") && $0.range(of: #" Item-\d+$"#, options: .regularExpression) != nil }
    }

    public static func run(defaults: UserDefaults) {
        guard !defaults.bool(forKey: doneKey) else { return }
        for key in legacyKeys(in: Array(defaults.dictionaryRepresentation().keys)) { defaults.removeObject(forKey: key) }
        defaults.set(true, forKey: doneKey)
    }
}

/// Display reconfiguration (plugging in or removing a monitor, waking) makes macOS shuffle status
/// item windows for a few seconds. Nothing should be concluded from item positions until it is quiet.
public struct DisplaySettle {
    public let quietPeriod: TimeInterval
    private var lastChange: Date?
    public init(quietPeriod: TimeInterval = 4) { self.quietPeriod = quietPeriod }

    public mutating func noteChange(at date: Date = Date()) { lastChange = date }

    public func isSettled(now: Date = Date()) -> Bool {
        guard let lastChange else { return true }
        return now.timeIntervalSince(lastChange) >= quietPeriod
    }
}
