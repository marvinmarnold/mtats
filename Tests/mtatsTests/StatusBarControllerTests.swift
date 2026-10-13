// SPDX-License-Identifier: MIT
import XCTest
@testable import mtats

final class StatusBarControllerTests: XCTestCase {
    // The ⚙ item delivers its click with `button.target = self; button.action = #selector(openSettings)`.
    // AppKit can only dispatch that to an NSObject that responds to the selector; a plain Swift class
    // receives nothing and the click silently does nothing.
    func test_settingsActionTarget_respondsToOpenSettings() {
        let defaults = UserDefaults(suiteName: "mtats.tests.\(UUID())")!
        let controller = StatusBarController(settings: SettingsStore(defaults: defaults), loader: PluginLoader(defaults: defaults))
        XCTAssertTrue(controller is NSObject, "status-item action targets must be NSObject subclasses")
        XCTAssertTrue((controller as AnyObject).responds(to: NSSelectorFromString("openSettings")))
    }

    // End to end through the real selector, as the button would: the Settings window appears.
    func test_openSettingsAction_createsTheSettingsWindow() {
        _ = NSApplication.shared
        let defaults = UserDefaults(suiteName: "mtats.tests.\(UUID())")!
        let controller = StatusBarController(settings: SettingsStore(defaults: defaults), loader: PluginLoader(defaults: defaults))
        (controller as AnyObject).perform(NSSelectorFromString("openSettings"))
        let window = NSApp.windows.first { $0.title == "mtats Settings" }
        XCTAssertNotNil(window)
        window?.close()
    }
}
