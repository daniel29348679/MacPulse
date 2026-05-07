import Darwin
import Foundation

final class CPUMonitor {
    struct Sample {
        let user: Double
        let system: Double
        let idle: Double
        var total: Double { user + system }
    }

    private var previousTicks: host_cpu_load_info?

    func sample() -> Sample {
        var size = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        var info = host_cpu_load_info()
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(size)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &size)
            }
        }

        guard result == KERN_SUCCESS else {
            return Sample(user: 0, system: 0, idle: 100)
        }

        defer { previousTicks = info }

        guard let prev = previousTicks else {
            return Sample(user: 0, system: 0, idle: 100)
        }

        let userDiff   = Double(info.cpu_ticks.0 &- prev.cpu_ticks.0)
        let systemDiff = Double(info.cpu_ticks.1 &- prev.cpu_ticks.1)
        let idleDiff   = Double(info.cpu_ticks.2 &- prev.cpu_ticks.2)
        let niceDiff   = Double(info.cpu_ticks.3 &- prev.cpu_ticks.3)

        let totalDiff = userDiff + systemDiff + idleDiff + niceDiff
        guard totalDiff > 0 else {
            return Sample(user: 0, system: 0, idle: 100)
        }

        return Sample(
            user:   (userDiff + niceDiff) / totalDiff * 100,
            system: systemDiff / totalDiff * 100,
            idle:   idleDiff / totalDiff * 100
        )
    }
}
