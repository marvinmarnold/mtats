// Tests/mtatsTests/SettingsStoreTests.swift
import XCTest
@testable import mtats

final class SettingsStoreTests: XCTestCase {
    func test_newWidgetDefaultsToEnabled() {
        let store = SettingsStore(defaults: UserDefaults(suiteName: "mtats.tests.\(UUID())")!)
        XCTAssertTrue(store.isEnabled(widgetID: "cpu"))
    }

    func test_disablingAWidget_persists() {
        let defaults = UserDefaults(suiteName: "mtats.tests.\(UUID())")!
        let store = SettingsStore(defaults: defaults)
        store.setEnabled(false, widgetID: "cpu")
        XCTAssertFalse(store.isEnabled(widgetID: "cpu"))
        let reloaded = SettingsStore(defaults: defaults)
        XCTAssertFalse(reloaded.isEnabled(widgetID: "cpu"))
    }

    func test_refreshIntervalDefaultsToOneSecond() {
        let store = SettingsStore(defaults: UserDefaults(suiteName: "mtats.tests.\(UUID())")!)
        XCTAssertEqual(store.refreshInterval, 1.0, accuracy: 0.001)
    }
}
