// SPDX-License-Identifier: MIT
import SwiftUI

/// A 3D cube reads as "graphics rendering", and is visually distinct from the CPU's chip glyph;
/// the previous monitor glyph looked like a display rather than a GPU.
enum GPUIcon { static let symbolName = "cube.transparent" }

public struct GPUMenuBarView: View {
    @ObservedObject var source: GPUMetricsSource
    public init(source: GPUMetricsSource) { self.source = source }
    public var body: some View {
        HStack(spacing: 3) {
            Image(systemName: GPUIcon.symbolName)
            Text(source.latest?.utilization.map { String(format: "%3.0f%%", $0 * 100) } ?? "  — ")
                .monospacedDigit()
                .frame(width: 30, alignment: .trailing)
        }
        .font(.system(size: 11, weight: .medium))
    }
}

public struct GPUDetailView: View {
    @ObservedObject var source: GPUMetricsSource
    public init(source: GPUMetricsSource) { self.source = source }
    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("GPU", systemImage: GPUIcon.symbolName).font(.headline)
            if let utilization = source.latest?.utilization {
                Text(String(format: "Utilization  %.0f%%", utilization * 100)).monospacedDigit()
            } else {
                Text("Not reported on this Mac.")
                Text("macOS did not expose GPU counters here. This is common inside virtual machines, which use a virtual GPU. It can also happen after a macOS update changes the counter name.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(width: 260, alignment: .leading)
    }
}
