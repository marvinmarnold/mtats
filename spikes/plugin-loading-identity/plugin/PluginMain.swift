import Foundation
import MTatsPluginKit

@objc(ConcreteWidget) class ConcreteWidget: NSObject, Widget {
    @objc func ping() -> String { "pong from plugin" }
}

@objc(PluginMain) public class PluginMain: NSObject, PluginEntry {
    @objc public static func makeWidgets() -> [Widget] {
        return [ConcreteWidget()]
    }
}
