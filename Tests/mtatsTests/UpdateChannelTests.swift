// SPDX-License-Identifier: MIT
import XCTest
@testable import mtats

final class UpdateChannelTests: XCTestCase {
    private func defaults() -> UserDefaults { UserDefaults(suiteName: "mtats.tests.\(UUID())")! }

    func test_noChannelSet_usesInfoPlistFeed() {
        XCTAssertNil(UpdateChannel.feedURLOverride(defaults: defaults()))
    }

    func test_betaChannel_overridesToBetaFeed() {
        let d = defaults(); d.set("beta", forKey: "updateChannel")
        XCTAssertEqual(UpdateChannel.feedURLOverride(defaults: d), "https://mtats.app/beta/appcast.xml")
    }

    func test_unknownChannel_isIgnored() {
        let d = defaults(); d.set("nightly", forKey: "updateChannel")
        XCTAssertNil(UpdateChannel.feedURLOverride(defaults: d))
    }

    // Review Focus: a debug package has no SUFeedURL and must never start the updater.
    func test_updaterDisabled_withoutFeedURL() {
        XCTAssertFalse(UpdateChannel.isEnabled(infoDictionary: ["CFBundleVersion": "1"], isSmokeTest: false))
        XCTAssertFalse(UpdateChannel.isEnabled(infoDictionary: nil, isSmokeTest: false))
    }

    func test_updaterDisabled_inSmokeTest() {
        XCTAssertFalse(UpdateChannel.isEnabled(infoDictionary: ["SUFeedURL": "https://mtats.app/appcast.xml"], isSmokeTest: true))
    }

    func test_updaterEnabled_forReleaseBuild() {
        XCTAssertTrue(UpdateChannel.isEnabled(infoDictionary: ["SUFeedURL": "https://mtats.app/appcast.xml"], isSmokeTest: false))
    }
}
