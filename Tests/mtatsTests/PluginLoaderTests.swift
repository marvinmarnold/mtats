// Tests/mtatsTests/PluginLoaderTests.swift
// SPDX-License-Identifier: MIT
import XCTest
@testable import mtats
import MTatsPluginKit

final class PluginLoaderTests: XCTestCase {
    func test_matchingAPIVersion_isCompatible() {
        let plist: [String: Any] = ["MTatsPluginAPIVersion": pluginAPIVersion]
        XCTAssertTrue(PluginLoader.isAPIVersionCompatible(infoDictionary: plist))
    }

    func test_mismatchedAPIVersion_isNotCompatible() {
        let plist: [String: Any] = ["MTatsPluginAPIVersion": pluginAPIVersion + 1]
        XCTAssertFalse(PluginLoader.isAPIVersionCompatible(infoDictionary: plist))
    }

    func test_missingAPIVersionKey_isNotCompatible() {
        XCTAssertFalse(PluginLoader.isAPIVersionCompatible(infoDictionary: [:]))
    }

    func test_ensureDirectoryExists_createsAMissingDirectoryRatherThanSkippingItSilently() {
        // Review Focus: a fresh install has never written to ~/Library/Application Support/mtats/Plugins —
        // the Host must create it, not silently skip watching it.
        let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let pluginsDir = tempRoot.appendingPathComponent("mtats/Plugins")
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        XCTAssertFalse(FileManager.default.fileExists(atPath: pluginsDir.path))
        PluginLoader().ensureDirectoryExists(pluginsDir)
        var isDirectory: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: pluginsDir.path, isDirectory: &isDirectory))
        XCTAssertTrue(isDirectory.boolValue)
    }

    // spec §4.2: third-party plugins get a one-time warning naming the signing identity
    // before first load — "one-time" persists across launches, so it's backed by UserDefaults
    // like SettingsStore, not an in-memory Set that resets every run.
    func test_newThirdPartyPlugin_hasNotBeenWarnedAboutYet() {
        let loader = PluginLoader(defaults: UserDefaults(suiteName: "mtats.tests.\(UUID())")!)
        XCTAssertFalse(loader.hasWarnedAboutThirdPartyPlugin(identifier: "com.example.plugin"))
    }

    func test_markingAThirdPartyPluginWarned_persists() {
        let defaults = UserDefaults(suiteName: "mtats.tests.\(UUID())")!
        let loader = PluginLoader(defaults: defaults)
        loader.markWarnedAboutThirdPartyPlugin(identifier: "com.example.plugin")
        XCTAssertTrue(loader.hasWarnedAboutThirdPartyPlugin(identifier: "com.example.plugin"))
        let reloaded = PluginLoader(defaults: defaults)
        XCTAssertTrue(reloaded.hasWarnedAboutThirdPartyPlugin(identifier: "com.example.plugin"))
    }

    func test_differentThirdPartyPlugin_isTrackedIndependently() {
        let defaults = UserDefaults(suiteName: "mtats.tests.\(UUID())")!
        let loader = PluginLoader(defaults: defaults)
        loader.markWarnedAboutThirdPartyPlugin(identifier: "com.example.pluginA")
        XCTAssertFalse(loader.hasWarnedAboutThirdPartyPlugin(identifier: "com.example.pluginB"))
    }

    // spec §4.2: rejected plugins (bad signature, API-version mismatch) get "a visible reason
    // in a diagnostics view" — tracked here as a published message list the Host can display,
    // since console prints are invisible in a GUI LSUIElement app with no attached terminal.
    func test_diagnosticMessages_startsEmpty() {
        let loader = PluginLoader()
        XCTAssertTrue(loader.diagnosticMessages.isEmpty)
    }

    // FSEvents re-scans the whole directory on any change (even Finder writing .DS_Store), so a
    // rejected bundle gets re-checked repeatedly — it must not pile up duplicate messages.
    func test_unsignedBundle_isSkippedWithOneDiagnostic_evenWhenScannedRepeatedly() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let builtIn = root.appendingPathComponent("builtin")
        let user = root.appendingPathComponent("user")
        try FileManager.default.createDirectory(at: user.appendingPathComponent("Unsigned.bundle/Contents"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: builtIn, withIntermediateDirectories: true)

        let loader = PluginLoader(defaults: UserDefaults(suiteName: "mtats.tests.\(UUID())")!)
        var warned = false
        let warn: (String) -> Bool = { _ in warned = true; return true }

        XCTAssertTrue(loader.loadAll(builtInDirectory: builtIn, userDirectory: user, warnBeforeFirstThirdPartyLoad: warn).isEmpty)
        XCTAssertTrue(loader.loadAll(builtInDirectory: builtIn, userDirectory: user, warnBeforeFirstThirdPartyLoad: warn).isEmpty)

        XCTAssertEqual(loader.diagnosticMessages.count, 1)
        XCTAssertTrue(loader.diagnosticMessages[0].contains("Unsigned.bundle"))
        XCTAssertFalse(warned, "an unsigned bundle is rejected outright — no trust prompt (spec §4.2)")
    }
}
