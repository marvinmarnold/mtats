// SPDX-License-Identifier: MIT
import AppKit
import Combine
import Sparkle

public enum UpdateChannel {
    public static let betaFeedURL = "https://mtats.app/beta/appcast.xml"

    /// nil means "use SUFeedURL from Info.plist" (stable). `defaults write com.mtats.app
    /// updateChannel beta` switches a test install to the beta feed (spec §Auto-update).
    public static func feedURLOverride(defaults: UserDefaults) -> String? {
        defaults.string(forKey: "updateChannel") == "beta" ? betaFeedURL : nil
    }

    /// Debug packages carry no SUFeedURL; the smoke test must make no network requests.
    public static func isEnabled(infoDictionary: [String: Any]?, isSmokeTest: Bool) -> Bool {
        guard !isSmokeTest, let feed = infoDictionary?["SUFeedURL"] as? String else { return false }
        return !feed.isEmpty
    }
}

final class UpdaterDelegate: NSObject, SPUUpdaterDelegate {
    private let defaults: UserDefaults
    init(defaults: UserDefaults) { self.defaults = defaults }
    func feedURLString(for updater: SPUUpdater) -> String? { UpdateChannel.feedURLOverride(defaults: defaults) }
}

/// LSUIElement apps aren't frontmost; without activating, Sparkle's window opens behind others.
final class UserDriverDelegate: NSObject, SPUStandardUserDriverDelegate {
    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        NSApp.activate()
    }
}

public final class UpdateControls: ObservableObject {
    @Published public private(set) var canCheckForUpdates = false
    private let updater: SPUUpdater
    private var cancellable: AnyCancellable?

    init(updater: SPUUpdater) {
        self.updater = updater
        cancellable = updater.publisher(for: \.canCheckForUpdates)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.canCheckForUpdates = $0 }
    }

    public func checkForUpdates() {
        NSApp.activate()
        updater.checkForUpdates()
    }

    public var automaticallyChecks: Bool {
        get { updater.automaticallyChecksForUpdates }
        set { objectWillChange.send(); updater.automaticallyChecksForUpdates = newValue }
    }
}
