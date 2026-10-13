// Plugins/GPUWidget/PluginMain.swift
// SPDX-License-Identifier: MIT
import Foundation
import SwiftUI
import MTatsPluginKit
import GPUCore

@objc(GPUWidgetAdapter) class GPUWidgetAdapter: NSObject, MTatsWidget {
    let id = "gpu"
    let displayName = "GPU"
    private let source = GPUMetricsSource()
    func start(interval: TimeInterval) { source.start(interval: interval) }
    func stop() { source.stop() }
    func menuBarView() -> AnyView { AnyView(GPUMenuBarView(source: source)) }
    func detailView() -> AnyView { AnyView(GPUDetailView(source: source)) }
}

@objc(GPUPluginMain) public class GPUPluginMain: NSObject, PluginEntry {
    public static func makeWidgets() -> [MTatsWidget] { [GPUWidgetAdapter()] }
}
