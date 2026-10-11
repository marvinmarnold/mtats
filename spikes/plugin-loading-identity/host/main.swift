import Foundation
import MTatsPluginKit

print("Host: kitBuildMarker=\(kitBuildMarker())")

let pluginPath = CommandLine.arguments[1]
guard let bundle = Bundle(path: pluginPath) else {
    print("Host: FAILED to construct Bundle at \(pluginPath)")
    exit(1)
}

guard bundle.load() else {
    print("Host: FAILED bundle.load()")
    exit(1)
}
print("Host: bundle loaded OK")

guard let principal = bundle.principalClass else {
    print("Host: FAILED no principalClass")
    exit(1)
}
print("Host: principalClass = \(principal)")

guard let entry = principal as? PluginEntry.Type else {
    print("Host: FAILED principalClass does not conform to PluginEntry (TYPE IDENTITY MISMATCH)")
    exit(1)
}
print("Host: principalClass conforms to PluginEntry \u{2713}")

let widgets = entry.makeWidgets()
print("Host: got \(widgets.count) widget(s)")

for w in widgets {
    // Independent conformance check, mirroring what the Host would really do.
    if let w2 = w as? Widget {
        print("Host: widget as? Widget succeeded \u{2713} ping() = \(w2.ping())")
    } else {
        print("Host: widget as? Widget FAILED (TYPE IDENTITY MISMATCH)")
    }
}
