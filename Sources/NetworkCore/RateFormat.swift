// SPDX-License-Identifier: MIT
import Foundation

/// Fixed-width throughput text. The unit is padded to the same length as the widest unit, so
/// the rendered string never changes width as the magnitude changes.
public enum RateFormat {
    private static let units = ["B/s", "KB/s", "MB/s", "GB/s", "TB/s"]

    public static func string(_ bytesPerSec: Double) -> String {
        var value = max(bytesPerSec, 0)
        var index = 0
        while value >= 1024, index < units.count - 1 {
            value /= 1024
            index += 1
        }
        let unit = units[index].padding(toLength: 5, withPad: " ", startingAt: 0)
        return String(format: "%5.1f %@", value, unit)
    }
}
