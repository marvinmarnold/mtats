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

    /// One current reason per bundle filename. FSEvents re-scans the whole directory on any
    /// change, so appending blindly would pile up duplicates; and a bundle that failed mid-copy
    /// then loaded on a later event shouldn't leave a stale message behind.
    private var diagnosticsByBundle: [String: String] = [:] {
        didSet { diagnosticMessages = diagnosticsByBundle.keys.sorted().compactMap { diagnosticsByBundle[$0] } }
    }

    /// Bundles already loaded, declined, or currently being prompted for this session. Keeps a
    /// declined plugin from re-prompting on every unrelated directory event, and keeps a
    /// reentrant FSEvent delivered during the trust alert's modal loop from opening a second
    /// alert for the same bundle. Declines are session-scoped: the next launch asks again.
    private var handledBundlePaths: Set<String> = []

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
    /// (ad-hoc signatures, used throughout local dev/smoke-testing, carry no certificate —
    /// and critically, no verified identity at all: anyone can ad-hoc-sign anything).
    public func signingIdentity(bundlePath: URL) -> String {
        guard let info = signingInformation(bundlePath: bundlePath) else { return "unknown" }
        if let certificates = info[kSecCodeInfoCertificates as String] as? [SecCertificate],
           let firstCertificate = certificates.first,
           let summary = SecCertificateCopySubjectSummary(firstCertificate) as String? {
            return summary
        }
        return "unsigned (ad-hoc) — identity not verified"
    }

    /// A stable identifier for exactly this signed binary, used — instead of the plugin's
    /// own self-declared CFBundleIdentifier — as the one-time-warning key. A plugin author
    /// chooses their own CFBundleIdentifier, so keying on it would let a *different* signer
    /// ship a plugin re-using an already-trusted identifier and skip the warning entirely.
    /// kSecCodeInfoUnique is a hash of the actual signed code: it changes if a single byte of
    /// the binary changes, so it can't be reused to impersonate a previously-approved plugin.
    public func codeUniqueIdentifier(bundlePath: URL) -> String? {
        guard let info = signingInformation(bundlePath: bundlePath),
              let unique = info[kSecCodeInfoUnique as String] as? Data else { return nil }
        return unique.map { String(format: "%02x", $0) }.joined()
    }

    private func signingInformation(bundlePath: URL) -> [String: Any]? {
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(bundlePath as CFURL, [], &staticCode) == errSecSuccess, let code = staticCode else {
            return nil
        }
        var information: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &information) == errSecSuccess,
              let info = information as? [String: Any] else {
            return nil
        }
        return info
    }

    public func loadAll(builtInDirectory: URL, userDirectory: URL, warnBeforeFirstThirdPartyLoad: (String) -> Bool = { _ in true }) -> [MTatsWidget] {
        ensureDirectoryExists(userDirectory)
        var widgets: [MTatsWidget] = []
        for (directory, isThirdParty) in [(builtInDirectory, false), (userDirectory, true)] {
            for entry in bundles(in: directory) {
                widgets.append(contentsOf: load(bundleAt: entry, isThirdParty: isThirdParty, warnBeforeFirstThirdPartyLoad: warnBeforeFirstThirdPartyLoad))
            }
        }
        return widgets
    }

    /// Sorted, because contentsOfDirectory's order is unspecified and it becomes menu-bar order.
    private func bundles(in directory: URL) -> [URL] {
        guard let entries = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return [] }
        return entries.filter { $0.pathExtension == "bundle" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// `warnBeforeFirstThirdPartyLoad` returns whether to proceed. A decline is remembered for
    /// this session only (see `handledBundlePaths`) — the next launch asks again rather than
    /// permanently blacklisting the plugin.
    private func load(bundleAt path: URL, isThirdParty: Bool, warnBeforeFirstThirdPartyLoad: (String) -> Bool) -> [MTatsWidget] {
        let name = path.lastPathComponent
        guard !handledBundlePaths.contains(path.path) else { return [] }
        guard hasValidSignature(bundlePath: path) else {
            diagnosticsByBundle[name] = "Skipped \(name): invalid or missing signature"
            return []
        }
        guard let bundle = Bundle(url: path), let info = bundle.infoDictionary,
              Self.isAPIVersionCompatible(infoDictionary: info) else {
            diagnosticsByBundle[name] = "Skipped \(name): incompatible or unreadable plugin API version"
            return []
        }
        handledBundlePaths.insert(path.path)
        if isThirdParty {
            // Keyed on the signed code's own hash, not the plugin's self-declared
            // CFBundleIdentifier (see codeUniqueIdentifier's doc comment) — falls back to the
            // bundle identifier only if the signing info is unexpectedly unreadable, which
            // can't happen once hasValidSignature above has already succeeded.
            let warnKey = codeUniqueIdentifier(bundlePath: path) ?? (info["CFBundleIdentifier"] as? String) ?? name
            if !hasWarnedAboutThirdPartyPlugin(identifier: warnKey) {
                guard warnBeforeFirstThirdPartyLoad(signingIdentity(bundlePath: path)) else {
                    diagnosticsByBundle[name] = "Skipped \(name): declined at the third-party load warning"
                    return []
                }
                markWarnedAboutThirdPartyPlugin(identifier: warnKey)
            }
        }
        guard bundle.load(), let principal = bundle.principalClass as? PluginEntry.Type else {
            diagnosticsByBundle[name] = "Skipped \(name): failed to load or find PluginEntry"
            return []
        }
        diagnosticsByBundle[name] = nil
        return principal.makeWidgets()
    }

    /// spec §4.2: the third-party directory is watched so a new plugin loads without a
    /// relaunch. FSEventStream is a C API; wrap it in a small class so the closure-based
    /// callback has somewhere to route back into Swift.
    public func watchForNewPlugins(in directory: URL, warnBeforeFirstThirdPartyLoad: @escaping (String) -> Bool = { _ in true }, onNewWidgets: @escaping ([MTatsWidget]) -> Void) -> PluginDirectoryWatcher {
        let watcher = PluginDirectoryWatcher(directory: directory) { [weak self] in
            guard let self else { return }
            let newWidgets = self.bundles(in: directory)
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
