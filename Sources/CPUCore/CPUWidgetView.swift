// SPDX-License-Identifier: MIT
import SwiftUI

public struct CPUMenuBarView: View {
    @ObservedObject var source: CPUMetricsSource
    public init(source: CPUMetricsSource) { self.source = source }
    public var body: some View {
        Text(String(format: "CPU %.0f%%", (source.latest?.totalUsage ?? 0) * 100))
            .font(.system(size: 11, design: .monospaced))
    }
}

public struct CPUDetailView: View {
    @ObservedObject var source: CPUMetricsSource
    public init(source: CPUMetricsSource) { self.source = source }
    public var body: some View {
        VStack(alignment: .leading) {
            Text("CPU").font(.headline)
            if let snapshot = source.latest {
                ForEach(Array(snapshot.perCoreUsage.enumerated()), id: \.offset) { index, usage in
                    Text(String(format: "Core %d: %.0f%%", index, usage * 100))
                }
            } else {
                Text("Waiting for data...")
            }
        }.padding()
    }
}
