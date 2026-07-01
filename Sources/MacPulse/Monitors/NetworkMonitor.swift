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
        guard let (totalIn, totalOut) = readInterfaceCounters() else {
            return Sample(downloadBytesPerSec: 0, uploadBytesPerSec: 0)
        }
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

    /// 排除 loopback 與虛擬介面（utun/awdl/llw/bridge/anpi 等內部流量）
    private static let excludedPrefixes = ["lo", "utun", "awdl", "llw", "bridge", "anpi", "gif", "stf"]

    private static func isExcluded(_ name: String) -> Bool {
        excludedPrefixes.contains { name.hasPrefix($0) }
    }

    /// sockaddr_dl 內 sdl_data（介面名稱起點）的 byte offset。
    private static let sdlDataOffset = MemoryLayout<sockaddr_dl>.offset(of: \.sdl_data) ?? 8

    /// 用 `sysctl(NET_RT_IFLIST2)` 讀 64-bit 介面計數器（`if_data64`）。
    /// 不能用 getifaddrs — 它給的 `if_data` counter 是 32-bit，每個介面
    /// 每累積 4 GiB 就繞回，高流量下速率會週期性掉到 0 並遺失統計。
    /// internal（非 private）是為了讓測試直接驗證 counter 單調遞增。
    func readInterfaceCounters() -> (UInt64, UInt64)? {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]

        // 探測大小與實際讀取之間介面數可能增加 → 預留 slack 並重試幾次
        for _ in 0..<3 {
            var needed = 0
            guard sysctl(&mib, u_int(mib.count), nil, &needed, nil, 0) == 0, needed > 0 else {
                return nil
            }
            var buffer = [UInt8](repeating: 0, count: needed + 1024)
            var size = buffer.count
            guard sysctl(&mib, u_int(mib.count), &buffer, &size, nil, 0) == 0 else {
                continue
            }
            return Self.parseInterfaceCounters(buffer: buffer, size: size)
        }
        return nil
    }

    /// 走訪 routing 訊息串流，加總所有實體介面的 in/out bytes。
    /// Layout: 連續的 if_msghdr（以 ifm_msglen 前進）；RTM_IFINFO2 的紀錄
    /// 是 if_msghdr2 + sockaddr_dl（介面名稱在 sdl_data 的前 sdl_nlen bytes）。
    private static func parseInterfaceCounters(buffer: [UInt8], size: Int) -> (UInt64, UInt64)? {
        var totalIn: UInt64 = 0
        var totalOut: UInt64 = 0
        var foundInterface = false

        buffer.withUnsafeBytes { raw in
            var offset = 0
            while offset + MemoryLayout<if_msghdr>.size <= size {
                let header = raw.loadUnaligned(fromByteOffset: offset, as: if_msghdr.self)
                let msgLen = Int(header.ifm_msglen)
                guard msgLen > 0 else { break }   // malformed 資料 → 停止，避免死迴圈
                defer { offset += msgLen }

                guard Int32(header.ifm_type) == RTM_IFINFO2,
                      offset + MemoryLayout<if_msghdr2>.size <= size else { continue }
                let ifm = raw.loadUnaligned(fromByteOffset: offset, as: if_msghdr2.self)

                let sdlOffset = offset + MemoryLayout<if_msghdr2>.size
                guard sdlOffset + MemoryLayout<sockaddr_dl>.size <= size else { continue }
                let sdl = raw.loadUnaligned(fromByteOffset: sdlOffset, as: sockaddr_dl.self)

                let nameLen = Int(sdl.sdl_nlen)
                let nameStart = sdlOffset + sdlDataOffset
                let msgEnd = min(size, offset + msgLen)
                guard nameLen > 0, nameStart + nameLen <= msgEnd else { continue }
                let name = String(decoding: raw[nameStart..<(nameStart + nameLen)], as: UTF8.self)
                guard !isExcluded(name) else { continue }

                foundInterface = true
                totalIn  &+= ifm.ifm_data.ifi_ibytes
                totalOut &+= ifm.ifm_data.ifi_obytes
            }
        }

        return foundInterface ? (totalIn, totalOut) : nil
    }
}
