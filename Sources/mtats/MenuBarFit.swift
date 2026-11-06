// Sources/mtats/MenuBarFit.swift
// SPDX-License-Identifier: MIT
import CoreGraphics

/// Pure decisions about fitting our indicators into the menu bar. On a notched display macOS
/// silently hides any status item that doesn't fit to the right of the notch, and an app can't
/// claim more room; the only remedy is to take less (see StatusBarController's combined mode).
public enum MenuBarFit {
    public static let edgePadding: CGFloat = 2
    public static let slotGap: CGFloat = 3

    /// Where status items can actually appear: right of the notch when there is one.
    public static func usableArea(screenFrame: CGRect, rightOfNotch: CGRect?) -> CGRect {
        rightOfNotch ?? screenFrame
    }

    /// `itemFrame` is the status item's window frame in screen coordinates (nil when it has no window).
    public static func isHidden(itemFrame: CGRect?, hasScreen: Bool, usable: CGRect) -> Bool {
        guard let itemFrame, hasScreen else { return true }
        return itemFrame.minX < usable.minX - 0.5 || itemFrame.maxX > usable.maxX + 0.5
    }

    /// Positions content widths left to right inside one status item.
    public static func layout(widths: [CGFloat]) -> (offsets: [CGFloat], total: CGFloat) {
        guard !widths.isEmpty else { return ([], 0) }
        var offsets: [CGFloat] = []
        var x = edgePadding
        for width in widths {
            offsets.append(x)
            x += width + slotGap
        }
        return (offsets, x - slotGap + edgePadding)
    }
}

/// One odd reading (display waking, a Space switch) must not permanently collapse the bar.
public struct HiddenDebounce {
    public static let threshold = 2
    private var streak = 0
    public init() {}

    /// Returns true once `threshold` consecutive readings were hidden.
    public mutating func record(hidden: Bool) -> Bool {
        streak = hidden ? streak + 1 : 0
        return streak >= Self.threshold
    }

    public mutating func reset() { streak = 0 }
}
