// Plugins/RAMWidget/PluginMain.swift
// SPDX-License-Identifier: MIT
import Foundation
import SwiftUI
import MTatsPluginKit
import RAMCore

@objc(RAMWidgetAdapter) class RAMWidgetAdapter: NSObject, MTatsWidget {
    let id = "ram"
    let displayName = "RAM"
    private let source = RAMMetricsSource()
    func start(interval: TimeInterval) { source.start(interval: interval) }
    func stop() { source.stop() }
    func menuBarView() -> AnyView { AnyView(RAMMenuBarView(source: source)) }
    func detailView() -> AnyView { AnyView(RAMDetailView(source: source)) }
}

@objc(RAMPluginMain) public class RAMPluginMain: NSObject, PluginEntry {
    public static func makeWidgets() -> [MTatsWidget] { [RAMWidgetAdapter()] }
}
