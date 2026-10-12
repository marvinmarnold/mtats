// SPDX-License-Identifier: MIT
import SwiftUI

public struct NetworkMenuBarView: View {
    @ObservedObject var source: NetworkMetricsSource
    public init(source: NetworkMetricsSource) { self.source = source }
    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            rateRow("arrow.down", .blue, source.latest?.rxBytesPerSec ?? 0)
            rateRow("arrow.up", .orange, source.latest?.txBytesPerSec ?? 0)
        }
        .font(.system(size: 9, weight: .medium))
    }

    private func rateRow(_ symbol: String, _ tint: Color, _ bytesPerSec: Double) -> some View {
        HStack(spacing: 2) {
            Image(systemName: symbol).foregroundStyle(tint).frame(width: 8)
            Text(RateFormat.string(bytesPerSec)).monospacedDigit()
        }
    }
}

public struct NetworkDetailView: View {
    @ObservedObject var source: NetworkMetricsSource
    public init(source: NetworkMetricsSource) { self.source = source }
    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Network", systemImage: "network").font(.headline)
            if let s = source.latest {
                rateLine("arrow.down", .blue, "Download", s.rxBytesPerSec)
                rateLine("arrow.up", .orange, "Upload", s.txBytesPerSec)
                Divider()
                infoRow("Local IP", s.localIPv4 ?? "unavailable")
                if source.publicIPLookupEnabled {
                    infoRow("Public IP", s.publicIP ?? "unavailable")
                    Button("Refresh public IP") { source.refreshPublicIPNow() }
                        .controlSize(.small)
                } else {
                    infoRow("Public IP", "lookup off")
                }
                ForEach(Array(s.perInterface.keys.sorted()), id: \.self) { name in
                    infoRow(name, RateFormat.string(s.perInterface[name] ?? 0))
                }
            } else {
                Text("Waiting for data…").foregroundStyle(.secondary)
            }
        }
        .font(.system(size: 11))
        .padding(12)
        .frame(width: 260, alignment: .leading)
    }

    private func rateLine(_ symbol: String, _ tint: Color, _ label: String, _ bytesPerSec: Double) -> some View {
        HStack {
            Image(systemName: symbol).foregroundStyle(tint).frame(width: 12)
            Text(label)
            Spacer()
            Text(RateFormat.string(bytesPerSec)).monospacedDigit()
        }
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).monospacedDigit().textSelection(.enabled)
        }
    }
}
