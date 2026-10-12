// SPDX-License-Identifier: MIT
import SwiftUI

public struct GPUMenuBarView: View {
    @ObservedObject var source: GPUMetricsSource
    public init(source: GPUMetricsSource) { self.source = source }
    public var body: some View {
        if let utilization = source.latest?.utilization {
            Text(String(format: "GPU %.0f%%", utilization * 100)).font(.system(size: 11, design: .monospaced))
        } else {
            Text("GPU N/A").font(.system(size: 11, design: .monospaced))
        }
    }
}

public struct GPUDetailView: View {
    @ObservedObject var source: GPUMetricsSource
    public init(source: GPUMetricsSource) { self.source = source }
    public var body: some View {
        VStack(alignment: .leading) {
            Text("GPU").font(.headline)
            if let utilization = source.latest?.utilization {
                Text(String(format: "Utilization: %.0f%%", utilization * 100))
            } else {
                Text("Utilization: N/A")
            }
        }.padding()
    }
}
