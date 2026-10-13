// SPDX-License-Identifier: MIT
import Foundation
import Darwin

public final class CPUMetricsSource: ObservableObject {
    @Published public private(set) var latest: CPUSnapshot?

    private var timer: Timer?
    private var previousLoads: [host_cpu_load_info]?

    public init() {}

    public func start(interval: TimeInterval = 1.0) {
        stop()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
        previousLoads = nil
    }

    private func tick() {
        guard let current = Self.readProcessorLoads() else { return }
        if let previous = previousLoads {
            latest = CPUCalculator.usage(previous: previous, current: current)
        }
        previousLoads = current
    }

    private static func readProcessorLoads() -> [host_cpu_load_info]? {
        var cpuCount: natural_t = 0
        var infoArray: processor_info_array_t!
        var infoCount: mach_msg_type_number_t = 0

        let result = host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &cpuCount, &infoArray, &infoCount)
        guard result == KERN_SUCCESS else { return nil }
        defer {
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: infoArray), vm_size_t(Int(infoCount) * MemoryLayout<integer_t>.stride))
        }

        let loadInfo = infoArray.withMemoryRebound(to: processor_cpu_load_info.self, capacity: Int(cpuCount)) { ptr in
            (0..<Int(cpuCount)).map { i -> host_cpu_load_info in
                var info = host_cpu_load_info()
                info.cpu_ticks.0 = UInt32(ptr[i].cpu_ticks.0)
                info.cpu_ticks.1 = UInt32(ptr[i].cpu_ticks.1)
                info.cpu_ticks.2 = UInt32(ptr[i].cpu_ticks.2)
                info.cpu_ticks.3 = UInt32(ptr[i].cpu_ticks.3)
                return info
            }
        }
        return loadInfo
    }
}
