// SPDX-License-Identifier: MIT
import CoreGraphics
import Foundation

public enum WidgetLifecycleAction: Equatable {
    case start(TimeInterval)
    case stop
    case none
}

/// Pure decisions behind StatusBarController, kept out of the AppKit code so they're testable.
public enum WidgetLifecycle {
    /// `runningInterval` is the interval the widget was last started at, or nil if stopped.
    public static func action(runningInterval: TimeInterval?, enabled: Bool, interval: TimeInterval) -> WidgetLifecycleAction {
        switch (enabled, runningInterval) {
        case (false, nil): return .none
        case (false, .some): return .stop
        case (true, nil): return .start(interval)
        case (true, .some(let current)): return current == interval ? .none : .start(interval)
        }
    }

    public static let itemPadding: CGFloat = 8

    /// Grow-only, so a value changing digit count doesn't shift every item to its left.
    public static func itemWidth(current: CGFloat, measured: CGFloat) -> CGFloat {
        max(current, (measured + itemPadding).rounded(.up))
    }
}

/// Where the Settings window opens: hanging just under the menu bar beneath the ⚙ item (like a
/// dropdown), not centered on screen, which left it far from the menu it was opened from.
public enum SettingsPlacement {
    public static let gap: CGFloat = 4

    /// Bottom-left origin in AppKit screen coordinates. `anchor` is the status item's window
    /// frame; `visible` is the screen's visibleFrame (already excludes the menu bar).
    public static func origin(size: CGSize, below anchor: CGRect, in visible: CGRect) -> CGPoint {
        let x = min(max(anchor.midX - size.width / 2, visible.minX), visible.maxX - size.width)
        return CGPoint(x: x, y: anchor.minY - gap - size.height)
    }
}
