import Darwin
import Foundation

final class MemoryMonitor {
    struct Sample {
        let usedBytes: UInt64
        let totalBytes: UInt64
        var usagePercent: Double {
            guard totalBytes > 0 else { return 0 }
            return Double(usedBytes) / Double(totalBytes) * 100
        }
    }

    private let totalBytes: UInt64 = ProcessInfo.processInfo.physicalMemory
    private let pageSize: UInt64 = UInt64(vm_kernel_page_size)

    func sample() -> Sample {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }

        guard result == KERN_SUCCESS else {
            return Sample(usedBytes: 0, totalBytes: totalBytes)
        }

        // macOS Activity Monitor 的「已使用」≈ active + wired + compressed
        let active     = UInt64(stats.active_count)     * pageSize
        let wired      = UInt64(stats.wire_count)       * pageSize
        let compressed = UInt64(stats.compressor_page_count) * pageSize

        return Sample(
            usedBytes: active + wired + compressed,
            totalBytes: totalBytes
        )
    }
}
