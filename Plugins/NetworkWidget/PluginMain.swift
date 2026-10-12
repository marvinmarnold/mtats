// Plugins/NetworkWidget/PluginMain.swift
// SPDX-License-Identifier: MIT
import Foundation
import SwiftUI
import MTatsPluginKit
import NetworkCore

@objc(NetworkWidgetAdapter) class NetworkWidgetAdapter: NSObject, MTatsWidget, PublicIPToggleable {
    let id = "network"
    let displayName = "Network"
    private let source = NetworkMetricsSource()
    func start(interval: TimeInterval) { source.start(interval: interval) }
    func stop() { source.stop() }
    func menuBarView() -> AnyView { AnyView(NetworkMenuBarView(source: source)) }
    func detailView() -> AnyView { AnyView(NetworkDetailView(source: source)) }
    func setPublicIPLookupEnabled(_ enabled: Bool) { source.setPublicIPLookupEnabled(enabled) }
}

@objc(NetworkPluginMain) public class NetworkPluginMain: NSObject, PluginEntry {
    public static func makeWidgets() -> [MTatsWidget] { [NetworkWidgetAdapter()] }
}
