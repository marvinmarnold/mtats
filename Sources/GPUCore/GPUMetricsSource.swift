// SPDX-License-Identifier: MIT
import Foundation
import IOKit

public final class GPUMetricsSource: ObservableObject {
    @Published public private(set) var latest: GPUSnapshot?
    private var timer: Timer?

    public init() {}

    public func start(interval: TimeInterval = 1.0) {
        stop()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer!, forMode: .common)
        tick()
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        latest = GPUSnapshot(utilization: Self.readUtilization())
    }

    /// Returns nil (never crashes) if no matching accelerator service or no usable key is
    /// found — Review Focus: this is the widget most likely to break across macOS versions.
    private static func readUtilization() -> Double? {
        var iterator: io_iterator_t = 0
        let matching = IOServiceMatching("IOAccelerator")
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }

        var service = IOIteratorNext(iterator)
        while service != 0 {
            defer { IOObjectRelease(service); service = IOIteratorNext(iterator) }
            guard let props = IORegistryEntryCreateCFProperty(service, "PerformanceStatistics" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? [String: Any] else { continue }
            if let value = GPUCalculator.utilization(fromPerformanceStatistics: props) {
                return value
            }
        }
        return nil
    }
}
