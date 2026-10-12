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

/// spec §4.2: third-party plugins get a one-time warning naming the signing identity
/// before first load — shown synchronously, before that plugin's code ever runs.
func warnBeforeFirstThirdPartyLoad(identity: String) {
    let alert = NSAlert()
    alert.messageText = "New third-party plugin"
    alert.informativeText = "A plugin signed by \"\(identity)\" is being loaded for the first time. Third-party plugins run with the same access to your Mac as mtats itself."
    alert.addButton(withTitle: "OK")
    alert.runModal()
}

let widgets = loader.loadAll(builtInDirectory: builtInDirectory, userDirectory: userDirectory, warnBeforeFirstThirdPartyLoad: warnBeforeFirstThirdPartyLoad)
let statusBar = StatusBarController(settings: settings, loader: loader)
statusBar.present(widgets: widgets)

// spec §4.2: third-party plugins hot-load without a relaunch. Held at top level so it
// isn't deallocated (which would stop the FSEventStream) — main.swift has no owner above it.
let watcher = loader.watchForNewPlugins(in: userDirectory, warnBeforeFirstThirdPartyLoad: warnBeforeFirstThirdPartyLoad) { newWidgets in
    statusBar.present(widgets: newWidgets)
}

if let index = CommandLine.arguments.firstIndex(where: { $0.hasPrefix("--smoke-test-exit-after=") }),
   let seconds = Double(CommandLine.arguments[index].split(separator: "=")[1]) {
    DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { exit(0) }
}

app.run()
