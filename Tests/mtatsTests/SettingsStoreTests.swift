// Tests/mtatsTests/SettingsStoreTests.swift
// SPDX-License-Identifier: MIT
import XCTest
import Combine
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

    // SettingsStore is an ObservableObject that SwiftUI views observe via @ObservedObject —
    // without publishing a change, a Settings UI showing e.g. "Refresh every 1.0s" stays
    // stale after the user moves the stepper, since nothing tells SwiftUI to re-render.
    func test_settingEnabled_publishesAChange() {
        let store = SettingsStore(defaults: UserDefaults(suiteName: "mtats.tests.\(UUID())")!)
        var fired = false
        let cancellable = store.objectWillChange.sink { fired = true }
        store.setEnabled(false, widgetID: "cpu")
        XCTAssertTrue(fired)
        cancellable.cancel()
    }

    func test_settingRefreshInterval_publishesAChange() {
        let store = SettingsStore(defaults: UserDefaults(suiteName: "mtats.tests.\(UUID())")!)
        var fired = false
        let cancellable = store.objectWillChange.sink { fired = true }
        store.refreshInterval = 2.0
        XCTAssertTrue(fired)
        cancellable.cancel()
    }

    func test_settingPublicIPLookupEnabled_publishesAChange() {
        let store = SettingsStore(defaults: UserDefaults(suiteName: "mtats.tests.\(UUID())")!)
        var fired = false
        let cancellable = store.objectWillChange.sink { fired = true }
        store.publicIPLookupEnabled = false
        XCTAssertTrue(fired)
        cancellable.cancel()
    }
}

final class CompactMenuBarSettingTests: XCTestCase {
    func test_compactMenuBar_defaultsOff_andPersists() {
        let defaults = UserDefaults(suiteName: "mtats.tests.\(UUID())")!
        let store = SettingsStore(defaults: defaults)
        XCTAssertFalse(store.compactMenuBar)
        store.compactMenuBar = true
        XCTAssertTrue(SettingsStore(defaults: defaults).compactMenuBar)
    }

    // Beta testers who turned on rc.1/rc.2's "Combine" toggle keep their choice.
    func test_compactMenuBar_honoursTheEarlierCombineSetting() {
        let defaults = UserDefaults(suiteName: "mtats.tests.\(UUID())")!
        defaults.set(true, forKey: "combineMenuBarItems")
        XCTAssertTrue(SettingsStore(defaults: defaults).compactMenuBar)
    }
}
