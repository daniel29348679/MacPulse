import Darwin
import Foundation

final class NetworkMonitor {
    struct Sample {
        let downloadBytesPerSec: Double
        let uploadBytesPerSec: Double
    }

    private var previousIn: UInt64 = 0
    private var previousOut: UInt64 = 0
    private var previousTime: Date?

    func sample() -> Sample {
        let (totalIn, totalOut) = readInterfaceCounters()
        let now = Date()

        defer {
            previousIn = totalIn
            previousOut = totalOut
            previousTime = now
        }

        guard let last = previousTime else {
            return Sample(downloadBytesPerSec: 0, uploadBytesPerSec: 0)
        }

        let elapsed = now.timeIntervalSince(last)
        guard elapsed > 0 else {
            return Sample(downloadBytesPerSec: 0, uploadBytesPerSec: 0)
        }

        let inDelta  = totalIn  >= previousIn  ? totalIn  - previousIn  : 0
        let outDelta = totalOut >= previousOut ? totalOut - previousOut : 0

        return Sample(
            downloadBytesPerSec: Double(inDelta) / elapsed,
            uploadBytesPerSec:   Double(outDelta) / elapsed
        )
    }

    private func readInterfaceCounters() -> (UInt64, UInt64) {
        var ifaddrPtr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddrPtr) == 0, let first = ifaddrPtr else {
            return (0, 0)
        }
        defer { freeifaddrs(ifaddrPtr) }

        var totalIn: UInt64 = 0
        var totalOut: UInt64 = 0

        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let ptr = cursor {
            defer { cursor = ptr.pointee.ifa_next }

            let addr = ptr.pointee.ifa_addr
            guard addr?.pointee.sa_family == UInt8(AF_LINK) else { continue }

            let name = String(cString: ptr.pointee.ifa_name)
            // 排除 loopback 與虛擬介面（utun/awdl/llw/bridge/anpi 等內部流量）
            if name.hasPrefix("lo") || name.hasPrefix("utun") || name.hasPrefix("awdl")
                || name.hasPrefix("llw") || name.hasPrefix("bridge") || name.hasPrefix("anpi")
                || name.hasPrefix("gif") || name.hasPrefix("stf") {
                continue
            }

            guard let dataPtr = ptr.pointee.ifa_data else { continue }
            let data = dataPtr.assumingMemoryBound(to: if_data.self).pointee
            totalIn  &+= UInt64(data.ifi_ibytes)
            totalOut &+= UInt64(data.ifi_obytes)
        }

        return (totalIn, totalOut)
    }
}
