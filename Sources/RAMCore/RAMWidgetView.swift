// SPDX-License-Identifier: MIT
import SwiftUI

public struct RAMMenuBarView: View {
    @ObservedObject var source: RAMMetricsSource
    public init(source: RAMMetricsSource) { self.source = source }
    public var body: some View {
        Text(String(format: "RAM %.0f%%", (source.latest?.usedFraction ?? 0) * 100))
            .font(.system(size: 11, design: .monospaced))
    }
}

public struct RAMDetailView: View {
    @ObservedObject var source: RAMMetricsSource
    public init(source: RAMMetricsSource) { self.source = source }
    public var body: some View {
        VStack(alignment: .leading) {
            Text("Memory").font(.headline)
            if let s = source.latest {
                Text("Wired: \(ByteCountFormatter.string(fromByteCount: Int64(s.wiredBytes), countStyle: .memory))")
                Text("Active: \(ByteCountFormatter.string(fromByteCount: Int64(s.activeBytes), countStyle: .memory))")
                Text("Inactive: \(ByteCountFormatter.string(fromByteCount: Int64(s.inactiveBytes), countStyle: .memory))")
                Text("Compressed: \(ByteCountFormatter.string(fromByteCount: Int64(s.compressedBytes), countStyle: .memory))")
                Text("Free: \(ByteCountFormatter.string(fromByteCount: Int64(s.freeBytes), countStyle: .memory))")
            } else {
                Text("Waiting for data...")
            }
        }.padding()
    }
}
