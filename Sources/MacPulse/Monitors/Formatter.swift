import Foundation

enum ByteFormatter {
    /// 給速率用：B/s, KB/s, MB/s（IEC 1024 進位，符合多數系統監控工具慣例）
    static func rate(_ bytesPerSec: Double) -> String {
        let bps = max(0, bytesPerSec)
        if bps < 1024 {
            return String(format: "%.0f B/s", bps)
        } else if bps < 1024 * 1024 {
            return String(format: "%.1f KB/s", bps / 1024)
        } else if bps < 1024 * 1024 * 1024 {
            return String(format: "%.1f MB/s", bps / (1024 * 1024))
        } else {
            return String(format: "%.2f GB/s", bps / (1024 * 1024 * 1024))
        }
    }

    /// 給容量用：MB / GB
    static func size(_ bytes: UInt64) -> String {
        let gb = Double(bytes) / (1024 * 1024 * 1024)
        if gb >= 1 {
            return String(format: "%.2f GB", gb)
        }
        let mb = Double(bytes) / (1024 * 1024)
        return String(format: "%.0f MB", mb)
    }
}
