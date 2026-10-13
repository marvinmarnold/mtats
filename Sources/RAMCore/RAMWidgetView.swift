// SPDX-License-Identifier: MIT
import SwiftUI

public struct RAMMenuBarView: View {
    @ObservedObject var source: RAMMetricsSource
    public init(source: RAMMetricsSource) { self.source = source }
    public var body: some View {
        let used = source.latest?.usedFraction ?? 0
        HStack(spacing: 3) {
            Image(systemName: "memorychip")
            Text(String(format: "%3.0f%%", used * 100))
                .monospacedDigit()
                .frame(width: 30, alignment: .trailing)
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(usageTint(used))
    }
}

public struct RAMDetailView: View {
    @ObservedObject var source: RAMMetricsSource
    public init(source: RAMMetricsSource) { self.source = source }
    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Memory", systemImage: "memorychip").font(.headline)
            if let s = source.latest {
                ProgressView(value: s.usedFraction).tint(usageTint(s.usedFraction))
                Text(String(format: "Used  %.0f%%", s.usedFraction * 100)).monospacedDigit().font(.system(size: 11))
                Divider()
                row("Wired", s.wiredBytes)
                row("Active", s.activeBytes)
                row("Inactive", s.inactiveBytes)
                row("Compressed", s.compressedBytes)
                row("Free", s.freeBytes)
            } else {
                Text("Waiting for data…").foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(width: 260, alignment: .leading)
    }

    private func row(_ label: String, _ bytes: UInt64) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .memory)).monospacedDigit()
        }
        .font(.system(size: 11))
    }
}

private func usageTint(_ fraction: Double) -> Color {
    switch fraction {
    case 0.9...: return .red
    case 0.75...: return .orange
    default: return .primary
    }
}
