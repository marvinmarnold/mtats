import Foundation

@objc(MTWidget) public protocol Widget: NSObjectProtocol {
    @objc func ping() -> String
}

@objc(MTPluginEntry) public protocol PluginEntry: NSObjectProtocol {
    @objc static func makeWidgets() -> [Widget]
}

public func kitBuildMarker() -> String { "kit-v1" }
