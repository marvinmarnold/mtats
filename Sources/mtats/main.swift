// Sources/mtats/main.swift
// SPDX-License-Identifier: MIT
import AppKit
import Foundation

let app = NSApplication.shared
app.setActivationPolicy(.accessory) // menu-bar only, no Dock icon

let settings = SettingsStore()
let loader = PluginLoader()
let builtInDirectory = Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/Plugins")
let userDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    .appendingPathComponent("mtats/Plugins")

/// smoke-test.sh asserts plugins actually load — a real, unattended `NSAlert.runModal()`
/// would hang that script forever the moment any third-party plugin is installed on the
/// machine running it (as HelloWidget.bundle genuinely is, from Task 11's dogfood proof).
/// The warning UX itself is covered by code review/this flag's absence in normal use, not by
/// the smoke test, so bypass it (loudly, to stdout) rather than block.
let isSmokeTest = CommandLine.arguments.contains { $0.hasPrefix("--smoke-test-exit-after=") }
if isSmokeTest {
    // stdout is fully buffered (not line-buffered) once redirected to a file/pipe instead of
    // a terminal — without this, smoke-test.sh's prints above wouldn't reach the log file
    // until the process actually exits, but the script reads the log while still running.
    setbuf(stdout, nil)
}

/// spec §4.2: third-party plugins get a one-time warning naming the signing identity
/// before first load — shown synchronously, before that plugin's code ever runs. Returns
/// whether to proceed: a user who reads "runs with the same access to your Mac as mtats
/// itself" needs a real way to say no, not just an acknowledgement.
func warnBeforeFirstThirdPartyLoad(identity: String) -> Bool {
    guard !isSmokeTest else {
        print("SMOKE_TEST_AUTO_APPROVED_THIRD_PARTY: \(identity)")
        return true
    }
    NSApp.activate(ignoringOtherApps: true) // this fires before any status item exists — without
    // activating, the alert can open behind other windows and look like a stalled launch.
    let alert = NSAlert()
    alert.messageText = "New third-party plugin"
    alert.informativeText = "A plugin signed by \"\(identity)\" wants to load for the first time. Third-party plugins run with the same access to your Mac as mtats itself."
    alert.addButton(withTitle: "Load")
    alert.addButton(withTitle: "Don't Load")
    return alert.runModal() == .alertFirstButtonReturn
}

let widgets = loader.loadAll(builtInDirectory: builtInDirectory, userDirectory: userDirectory, warnBeforeFirstThirdPartyLoad: warnBeforeFirstThirdPartyLoad)
if widgets.isEmpty {
    // ADR-0005's Task 10 addendum: a plain `swift build`/`swift run mtats` statically embeds
    // MTatsPluginKit into this executable instead of linking it dynamically, which makes
    // every plugin's PluginEntry cast silently fail with no error — exactly this symptom,
    // zero widgets, no crash. Only Scripts/package-app.sh's relink step avoids it.
    FileHandle.standardError.write("mtats: loaded zero widgets — if you built with plain `swift build`/`swift run`, use Scripts/package-app.sh instead (see ADR-0005's Task 10 addendum).\n".data(using: .utf8)!)
}
let statusBar = StatusBarController(settings: settings, loader: loader)
statusBar.present(widgets: widgets)

// spec §4.2: third-party plugins hot-load without a relaunch. Held at top level so it
// isn't deallocated (which would stop the FSEventStream) — main.swift has no owner above it.
let watcher = loader.watchForNewPlugins(in: userDirectory, warnBeforeFirstThirdPartyLoad: warnBeforeFirstThirdPartyLoad) { newWidgets in
    statusBar.present(widgets: newWidgets)
}

if let index = CommandLine.arguments.firstIndex(where: { $0.hasPrefix("--smoke-test-exit-after=") }),
   let seconds = Double(CommandLine.arguments[index].split(separator: "=")[1]) {
    // spec §8 step 5's smoke test needs to assert plugins actually loaded, not just that the
    // process stayed alive — that's exactly the regression Task 10 found and fixed (every
    // plugin silently failing its PluginEntry cast while the process ran fine). A GUI
    // LSUIElement app has no console in normal use, so this output only appears here.
    print("SMOKE_TEST_LOADED_WIDGET_IDS: \(widgets.map(\.id).sorted().joined(separator: ","))")
    for message in loader.diagnosticMessages {
        print("SMOKE_TEST_DIAGNOSTIC: \(message)")
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { exit(0) }
}

app.run()
