// Sources/mtats/PluginLoader.swift
// SPDX-License-Identifier: MIT
import Foundation
import CoreServices // FSEventStream, for PluginDirectoryWatcher below
import MTatsPluginKit

public final class PluginLoader {
    public init() {}

    public static func isAPIVersionCompatible(infoDictionary: [String: Any]) -> Bool {
        guard let declared = infoDictionary["MTatsPluginAPIVersion"] as? Int else { return false }
        return declared == pluginAPIVersion
    }

    public func hasValidSignature(bundlePath: URL) -> Bool {
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(bundlePath as CFURL, [], &staticCode) == errSecSuccess, let code = staticCode else { return false }
        return SecStaticCodeCheckValidity(code, [], nil) == errSecSuccess
    }

    /// Review Focus: the third-party directory may not exist yet on a fresh install.
    /// Create it rather than skip watching it silently.
    public func ensureDirectoryExists(_ directory: URL) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    public func loadAll(builtInDirectory: URL, userDirectory: URL) -> [MTatsWidget] {
        ensureDirectoryExists(userDirectory)
        var widgets: [MTatsWidget] = []
        for directory in [builtInDirectory, userDirectory] {
            guard let entries = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { continue }
            for entry in entries where entry.pathExtension == "bundle" {
                widgets.append(contentsOf: load(bundleAt: entry))
            }
        }
        return widgets
    }

    private func load(bundleAt path: URL) -> [MTatsWidget] {
        guard hasValidSignature(bundlePath: path) else {
            print("PluginLoader: skipping \(path.lastPathComponent) — invalid/missing signature")
            return []
        }
        guard let bundle = Bundle(url: path), let info = bundle.infoDictionary,
              Self.isAPIVersionCompatible(infoDictionary: info) else {
            print("PluginLoader: skipping \(path.lastPathComponent) — incompatible or unreadable plugin API version")
            return []
        }
        guard bundle.load(), let principal = bundle.principalClass as? PluginEntry.Type else {
            print("PluginLoader: skipping \(path.lastPathComponent) — failed to load or find PluginEntry")
            return []
        }
        return principal.makeWidgets()
    }

    /// spec §4.2: the third-party directory is watched so a new plugin loads without a
    /// relaunch. FSEventStream is a C API; wrap it in a small class so the closure-based
    /// callback has somewhere to route back into Swift.
    public func watchForNewPlugins(in directory: URL, onNewWidgets: @escaping ([MTatsWidget]) -> Void) -> PluginDirectoryWatcher {
        let watcher = PluginDirectoryWatcher(directory: directory) { [weak self] in
            guard let self, let entries = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return }
            let newWidgets = entries
                .filter { $0.pathExtension == "bundle" }
                .flatMap { self.load(bundleAt: $0) }
            if !newWidgets.isEmpty { onNewWidgets(newWidgets) }
        }
        watcher.start()
        return watcher
    }
}

/// Thin wrapper around FSEventStream. Kept separate from PluginLoader so PluginLoader's
/// core logic (signature/version checks) stays unit-testable without touching FSEvents.
public final class PluginDirectoryWatcher {
    private var stream: FSEventStreamRef?
    private let directory: URL
    private let onChange: () -> Void

    public init(directory: URL, onChange: @escaping () -> Void) {
        self.directory = directory
        self.onChange = onChange
    }

    public func start() {
        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            let watcher = Unmanaged<PluginDirectoryWatcher>.fromOpaque(info).takeUnretainedValue()
            watcher.onChange()
        }
        var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(), retain: nil, release: nil, copyDescription: nil)
        stream = FSEventStreamCreate(nil, callback, &context, [directory.path] as CFArray, FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 1.0, UInt32(kFSEventStreamCreateFlagNone))
        guard let stream else { return }
        FSEventStreamSetDispatchQueue(stream, DispatchQueue.main)
        FSEventStreamStart(stream)
    }

    public func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    deinit { stop() }
}
