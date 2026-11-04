// SPDX-License-Identifier: MIT
import XCTest
@testable import mtats

final class MenuBarFitTests: XCTestCase {
    // Notched 1512pt-wide display: the usable status area is right of the notch.
    let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
    let rightOfNotch = CGRect(x: 860, y: 950, width: 652, height: 32)

    func test_usableArea_isTheRightOfNotchRegion_whenThereIsANotch() {
        XCTAssertEqual(MenuBarFit.usableArea(screenFrame: screen, rightOfNotch: rightOfNotch), rightOfNotch)
    }

    func test_usableArea_isTheWholeScreen_withoutANotch() {
        XCTAssertEqual(MenuBarFit.usableArea(screenFrame: screen, rightOfNotch: nil), screen)
    }

    func test_itemInsideUsableArea_isNotHidden() {
        let item = CGRect(x: 1200, y: 950, width: 60, height: 24)
        XCTAssertFalse(MenuBarFit.isHidden(itemFrame: item, hasScreen: true, usable: rightOfNotch))
    }

    func test_itemUnderTheNotch_isHidden() {
        let item = CGRect(x: 780, y: 950, width: 60, height: 24)
        XCTAssertTrue(MenuBarFit.isHidden(itemFrame: item, hasScreen: true, usable: rightOfNotch))
    }

    func test_itemPartlyCutOffByTheNotch_isHidden() {
        let item = CGRect(x: 840, y: 950, width: 60, height: 24)
        XCTAssertTrue(MenuBarFit.isHidden(itemFrame: item, hasScreen: true, usable: rightOfNotch))
    }

    func test_itemParkedOffscreen_isHidden() {
        let item = CGRect(x: -4000, y: 950, width: 60, height: 24)
        XCTAssertTrue(MenuBarFit.isHidden(itemFrame: item, hasScreen: true, usable: rightOfNotch))
    }

    func test_itemWithNoWindowOrScreen_isHidden() {
        XCTAssertTrue(MenuBarFit.isHidden(itemFrame: nil, hasScreen: true, usable: rightOfNotch))
        XCTAssertTrue(MenuBarFit.isHidden(itemFrame: CGRect(x: 1200, y: 950, width: 60, height: 24), hasScreen: false, usable: rightOfNotch))
    }

    // A single odd reading (screen waking, space switch) must not permanently collapse the bar.
    func test_debounce_needsTwoConsecutiveHiddenReadings() {
        var debounce = HiddenDebounce()
        XCTAssertFalse(debounce.record(hidden: true))
        XCTAssertFalse(debounce.record(hidden: false))
        XCTAssertFalse(debounce.record(hidden: true))
        XCTAssertTrue(debounce.record(hidden: true))
    }

    func test_layout_placesSlotsLeftToRightWithGapsAndPadding() {
        let layout = MenuBarFit.layout(widths: [40, 50, 30])
        let expectedOffsets: [CGFloat] = [4, 50, 106]
        XCTAssertEqual(layout.offsets, expectedOffsets)
        XCTAssertEqual(layout.total, CGFloat(140))
    }

    func test_layout_ofNothing_isEmpty() {
        let layout = MenuBarFit.layout(widths: [])
        XCTAssertTrue(layout.offsets.isEmpty)
        XCTAssertEqual(layout.total, 0)
    }

    func test_combinedWidth_isNarrowerThanSeparateItems() {
        let widths: [CGFloat] = [40, 50, 30]
        let separate: CGFloat = widths.reduce(0) { $0 + $1 + WidgetLifecycle.itemPadding }
        let combined: CGFloat = MenuBarFit.layout(widths: widths).total
        XCTAssertLessThan(combined, separate, "combining must take less room than separate items")
    }
}
