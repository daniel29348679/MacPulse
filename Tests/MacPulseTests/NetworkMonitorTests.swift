import Foundation
@testable import MacPulse

enum NetworkMonitorTests {
    static let tests: [MacPulseTestCase] = [
        MacPulseTestCase("NetworkMonitor reads 64-bit interface counters", testCountersReadableAndMonotonic)
    ]

    static func testCountersReadableAndMonotonic() throws {
        // 冒煙測試 NET_RT_IFLIST2 解析路徑：實體介面（enN）一定列得出來，
        // 且 64-bit counter 只增不減 — 連讀兩次驗證單調遞增。
        let monitor = NetworkMonitor()
        let first = monitor.readInterfaceCounters()
        try expect(first != nil, "no interface counters readable")
        let second = monitor.readInterfaceCounters()
        try expect(second != nil, "second read returned no counters")
        if let (in1, out1) = first, let (in2, out2) = second {
            try expect(in2 >= in1, "download counter went backwards (\(in1) -> \(in2))")
            try expect(out2 >= out1, "upload counter went backwards (\(out1) -> \(out2))")
        }
    }
}
