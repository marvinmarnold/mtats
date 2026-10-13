// SPDX-License-Identifier: MIT
import SwiftUI

public struct CPUMenuBarView: View {
    @ObservedObject var source: CPUMetricsSource
    public init(source: CPUMetricsSource) { self.source = source }
    public var body: some View {
        let usage = source.latest?.totalUsage ?? 0
        HStack(spacing: 3) {
            Image(systemName: "cpu")
            Text(String(format: "%3.0f%%", usage * 100))
                .monospacedDigit()
                .frame(width: 30, alignment: .trailing)
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(usageTint(usage))
    }
}

public struct CPUDetailView: View {
    @ObservedObject var source: CPUMetricsSource
    public init(source: CPUMetricsSource) { self.source = source }
    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("CPU", systemImage: "cpu").font(.headline)
            if let snapshot = source.latest {
                Text(String(format: "Total  %.0f%%", snapshot.totalUsage * 100))
                    .monospacedDigit()
                ForEach(Array(snapshot.perCoreUsage.enumerated()), id: \.offset) { index, usage in
                    HStack(spacing: 8) {
                        Text("Core \(index + 1)").frame(width: 52, alignment: .leading)
                        ProgressView(value: usage).tint(usageTint(usage))
                        Text(String(format: "%3.0f%%", usage * 100)).monospacedDigit().frame(width: 36, alignment: .trailing)
                    }
                    .font(.system(size: 11))
                }
            } else {
                Text("Waiting for data…").foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(width: 260, alignment: .leading)
    }
}

/// Load-based colour: quiet until a core is genuinely busy, so the bar doesn't shout all day.
private func usageTint(_ fraction: Double) -> Color {
    switch fraction {
    case 0.9...: return .red
    case 0.75...: return .orange
    default: return .primary
    }
}
