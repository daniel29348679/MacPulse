@testable import MacPulse

enum ByteFormatterTests {
    static let tests: [MacPulseTestCase] = [
        MacPulseTestCase("ByteFormatter.rate formats boundaries", testRateFormatsBoundaries),
        MacPulseTestCase("ByteFormatter.size formats MB and GB", testSizeFormatsMegabytesAndGigabytes)
    ]

    static func testRateFormatsBoundaries() throws {
        try expectEqual(ByteFormatter.rate(-1), "0 B/s")
        try expectEqual(ByteFormatter.rate(0), "0 B/s")
        try expectEqual(ByteFormatter.rate(1023), "1023 B/s")
        try expectEqual(ByteFormatter.rate(1024), "1.0 KB/s")
        try expectEqual(ByteFormatter.rate(1024 * 1024), "1.0 MB/s")
        try expectEqual(ByteFormatter.rate(1024 * 1024 * 1024), "1.00 GB/s")
    }

    static func testSizeFormatsMegabytesAndGigabytes() throws {
        try expectEqual(ByteFormatter.size(0), "0 MB")
        try expectEqual(ByteFormatter.size(1024 * 1024), "1 MB")
        try expectEqual(ByteFormatter.size(512 * 1024 * 1024), "512 MB")
        try expectEqual(ByteFormatter.size(1024 * 1024 * 1024), "1.00 GB")
    }
}
