// SPDX-License-Identifier: MIT
import SwiftUI

private func formatRate(_ bytesPerSec: Double) -> String {
    ByteCountFormatter.string(fromByteCount: Int64(bytesPerSec), countStyle: .binary) + "/s"
}

public struct NetworkMenuBarView: View {
    @ObservedObject var source: NetworkMetricsSource
    public init(source: NetworkMetricsSource) { self.source = source }
    public var body: some View {
        Text("↓\(formatRate(source.latest?.rxBytesPerSec ?? 0)) ↑\(formatRate(source.latest?.txBytesPerSec ?? 0))")
            .font(.system(size: 11, design: .monospaced))
    }
}

public struct NetworkDetailView: View {
    @ObservedObject var source: NetworkMetricsSource
    public init(source: NetworkMetricsSource) { self.source = source }
    public var body: some View {
        VStack(alignment: .leading) {
            Text("Network").font(.headline)
            if let s = source.latest {
                Text("Local IP: \(s.localIPv4 ?? "unavailable")")
                if source.publicIPLookupEnabled {
                    Text("Public IP: \(s.publicIP ?? "unavailable")")
                } else {
                    Text("Public IP: lookup off (Settings)")
                }
                ForEach(Array(s.perInterface.keys.sorted()), id: \.self) { name in
                    Text("\(name): \(formatRate(s.perInterface[name] ?? 0))")
                }
                if source.publicIPLookupEnabled {
                    Button("Refresh public IP") { source.refreshPublicIPNow() }
                }
            } else {
                Text("Waiting for data...")
            }
        }.padding()
    }
}
