// Tests/mtatsTests/PluginLoaderTests.swift
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
}
