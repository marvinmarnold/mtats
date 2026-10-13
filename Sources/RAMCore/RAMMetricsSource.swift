// SPDX-License-Identifier: MIT
import Foundation
import Darwin

public final class RAMMetricsSource: ObservableObject {
    @Published public private(set) var latest: RAMSnapshot?
    private var timer: Timer?

    public init() {}

    public func start(interval: TimeInterval = 1.0) {
        stop()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(timer!, forMode: .common)
        tick()
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return }

        var pageSize: vm_size_t = 0
        host_page_size(mach_host_self(), &pageSize)

        let totalPhysical = ProcessInfo.processInfo.physicalMemory

        latest = RAMCalculator.snapshot(stats: stats, pageSize: UInt64(pageSize), totalPhysicalBytes: totalPhysical)
    }
}
