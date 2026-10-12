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

let widgets = loader.loadAll(builtInDirectory: builtInDirectory, userDirectory: userDirectory)
let statusBar = StatusBarController(settings: settings)
statusBar.present(widgets: widgets)

// spec §4.2: third-party plugins hot-load without a relaunch. Held at top level so it
// isn't deallocated (which would stop the FSEventStream) — main.swift has no owner above it.
let watcher = loader.watchForNewPlugins(in: userDirectory) { newWidgets in
    statusBar.present(widgets: newWidgets)
}

if let index = CommandLine.arguments.firstIndex(where: { $0.hasPrefix("--smoke-test-exit-after=") }),
   let seconds = Double(CommandLine.arguments[index].split(separator: "=")[1]) {
    DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { exit(0) }
}

app.run()
