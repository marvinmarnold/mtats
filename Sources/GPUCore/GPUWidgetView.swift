// SPDX-License-Identifier: MIT
import SwiftUI

/// SF Symbols has no graphics-card glyph (`cpu` and `memorychip` exist, `gpu` doesn't), so this draws
/// one: a card with a fan and a mounting bracket. Strokes use the foreground style, so it tints and
/// scales with the surrounding text like a symbol would.
struct GPUGlyph: View {
    var body: some View {
        Canvas { ctx, size in
            let u = min(size.width, size.height) / 16
            let stroke = StrokeStyle(lineWidth: 1.15 * u, lineCap: .round, lineJoin: .round)
            let ink = GraphicsContext.Shading.foreground
            ctx.stroke(Path(roundedRect: CGRect(x: 1 * u, y: 3.5 * u, width: 14 * u, height: 8 * u), cornerRadius: 1.5 * u), with: ink, style: stroke)
            ctx.stroke(Path(ellipseIn: CGRect(x: 6.2 * u, y: 5.2 * u, width: 4.6 * u, height: 4.6 * u)), with: ink, style: stroke)
            ctx.fill(Path(ellipseIn: CGRect(x: 7.7 * u, y: 6.7 * u, width: 1.6 * u, height: 1.6 * u)), with: ink)
            ctx.stroke(Path { $0.move(to: CGPoint(x: 3 * u, y: 11.5 * u)); $0.addLine(to: CGPoint(x: 3 * u, y: 14 * u)) }, with: ink, style: stroke)
            ctx.stroke(Path { $0.move(to: CGPoint(x: 5 * u, y: 13.5 * u)); $0.addLine(to: CGPoint(x: 13 * u, y: 13.5 * u)) }, with: ink,
                       style: StrokeStyle(lineWidth: 1.1 * u, lineCap: .round, dash: [1.2 * u, 1.4 * u]))
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

public struct GPUMenuBarView: View {
    @ObservedObject var source: GPUMetricsSource
    public init(source: GPUMetricsSource) { self.source = source }
    public var body: some View {
        HStack(spacing: 3) {
            GPUGlyph().frame(width: 13, height: 13)
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
            HStack(spacing: 4) { GPUGlyph().frame(width: 15, height: 15); Text("GPU") }.font(.headline)
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
