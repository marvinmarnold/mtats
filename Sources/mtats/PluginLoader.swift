// Sources/mtats/PluginLoader.swift
// SPDX-License-Identifier: MIT
import Combine
import Foundation
import CoreServices // FSEventStream, for PluginDirectoryWatcher below
import MTatsPluginKit

public final class PluginLoader: ObservableObject {
    /// spec §4.2: a rejected plugin (bad signature, API-version mismatch) must be skipped
    /// "with a visible reason in a diagnostics view" — a console print is invisible in a
    /// GUI LSUIElement app with no attached terminal, so the Host needs something it can
    /// actually render. This is that something.
    @Published public private(set) var diagnosticMessages: [String] = []

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

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

    /// spec §4.2: third-party plugins get a one-time warning naming the signing identity
    /// before first load. "One-time" means ever, not just this run, so it's persisted.
    public func hasWarnedAboutThirdPartyPlugin(identifier: String) -> Bool {
        defaults.bool(forKey: "thirdPartyPluginWarned.\(identifier)")
    }

    public func markWarnedAboutThirdPartyPlugin(identifier: String) {
        defaults.set(true, forKey: "thirdPartyPluginWarned.\(identifier)")
    }

    /// Human-readable signing identity for the one-time third-party warning: the signing
    /// certificate's common name when one exists, otherwise a clearly-labeled ad-hoc fallback
    /// (ad-hoc signatures, used throughout local dev/smoke-testing, carry no certificate).
    public func signingIdentity(bundlePath: URL) -> String {
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(bundlePath as CFURL, [], &staticCode) == errSecSuccess, let code = staticCode else {
            return "unknown"
        }
        var information: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &information) == errSecSuccess,
              let info = information as? [String: Any] else {
            return "unknown"
        }
        if let certificates = info[kSecCodeInfoCertificates as String] as? [SecCertificate],
           let firstCertificate = certificates.first,
           let summary = SecCertificateCopySubjectSummary(firstCertificate) as String? {
            return summary
        }
        if let identifier = info[kSecCodeInfoIdentifier as String] as? String {
            return "ad-hoc (\(identifier))"
        }
        return "ad-hoc (unverified identity)"
    }

    public func loadAll(builtInDirectory: URL, userDirectory: URL, warnBeforeFirstThirdPartyLoad: (String) -> Void = { _ in }) -> [MTatsWidget] {
        ensureDirectoryExists(userDirectory)
        var widgets: [MTatsWidget] = []
        for (directory, isThirdParty) in [(builtInDirectory, false), (userDirectory, true)] {
            guard let entries = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { continue }
            for entry in entries where entry.pathExtension == "bundle" {
                widgets.append(contentsOf: load(bundleAt: entry, isThirdParty: isThirdParty, warnBeforeFirstThirdPartyLoad: warnBeforeFirstThirdPartyLoad))
            }
        }
        return widgets
    }

    private func load(bundleAt path: URL, isThirdParty: Bool, warnBeforeFirstThirdPartyLoad: (String) -> Void) -> [MTatsWidget] {
        guard hasValidSignature(bundlePath: path) else {
            diagnosticMessages.append("Skipped \(path.lastPathComponent): invalid or missing signature")
            return []
        }
        guard let bundle = Bundle(url: path), let info = bundle.infoDictionary,
              Self.isAPIVersionCompatible(infoDictionary: info) else {
            diagnosticMessages.append("Skipped \(path.lastPathComponent): incompatible or unreadable plugin API version")
            return []
        }
        if isThirdParty {
            let identifier = (info["CFBundleIdentifier"] as? String) ?? path.lastPathComponent
            if !hasWarnedAboutThirdPartyPlugin(identifier: identifier) {
                warnBeforeFirstThirdPartyLoad(signingIdentity(bundlePath: path))
                markWarnedAboutThirdPartyPlugin(identifier: identifier)
            }
        }
        guard bundle.load(), let principal = bundle.principalClass as? PluginEntry.Type else {
            diagnosticMessages.append("Skipped \(path.lastPathComponent): failed to load or find PluginEntry")
            return []
        }
        return principal.makeWidgets()
    }

    /// spec §4.2: the third-party directory is watched so a new plugin loads without a
    /// relaunch. FSEventStream is a C API; wrap it in a small class so the closure-based
    /// callback has somewhere to route back into Swift.
    public func watchForNewPlugins(in directory: URL, warnBeforeFirstThirdPartyLoad: @escaping (String) -> Void = { _ in }, onNewWidgets: @escaping ([MTatsWidget]) -> Void) -> PluginDirectoryWatcher {
        let watcher = PluginDirectoryWatcher(directory: directory) { [weak self] in
            guard let self, let entries = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return }
            let newWidgets = entries
                .filter { $0.pathExtension == "bundle" }
                .flatMap { self.load(bundleAt: $0, isThirdParty: true, warnBeforeFirstThirdPartyLoad: warnBeforeFirstThirdPartyLoad) }
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
