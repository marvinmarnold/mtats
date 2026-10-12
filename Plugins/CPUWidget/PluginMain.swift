// Plugins/CPUWidget/PluginMain.swift
// SPDX-License-Identifier: MIT
import Foundation
import SwiftUI
import MTatsPluginKit
import CPUCore

@objc(CPUWidgetAdapter) class CPUWidgetAdapter: NSObject, MTatsWidget {
    let id = "cpu"
    let displayName = "CPU"
    private let source = CPUMetricsSource()
    func start(interval: TimeInterval) { source.start(interval: interval) }
    func stop() { source.stop() }
    func menuBarView() -> AnyView { AnyView(CPUMenuBarView(source: source)) }
    func detailView() -> AnyView { AnyView(CPUDetailView(source: source)) }
}

@objc(CPUPluginMain) public class CPUPluginMain: NSObject, PluginEntry {
    public static func makeWidgets() -> [MTatsWidget] { [CPUWidgetAdapter()] }
}
