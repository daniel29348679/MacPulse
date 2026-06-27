@testable import MacPulse

enum UpdaterTests {
    static let tests: [MacPulseTestCase] = [
        MacPulseTestCase("Updater compares numeric semantic segments", testSemanticVersionSegmentsCompareNumerically),
        MacPulseTestCase("Updater treats missing segments as zero", testMissingSegmentsAreTreatedAsZero),
        MacPulseTestCase("Updater ignores suffixes after numeric prefixes", testSuffixesAfterNumericPrefixAreIgnored)
    ]

    static func testSemanticVersionSegmentsCompareNumerically() throws {
        try expect(Updater.isNewer("1.2.10", than: "1.2.9"))
        try expect(Updater.isNewer("2.0", than: "1.99.99"))
        try expect(!Updater.isNewer("1.2.9", than: "1.2.10"))
    }

    static func testMissingSegmentsAreTreatedAsZero() throws {
        try expect(!Updater.isNewer("1.2", than: "1.2.0"))
        try expect(!Updater.isNewer("1.2.0", than: "1.2"))
        try expect(Updater.isNewer("1.2.1", than: "1.2"))
    }

    static func testSuffixesAfterNumericPrefixAreIgnored() throws {
        try expect(Updater.isNewer("1.2.3-beta", than: "1.2.2"))
        try expect(!Updater.isNewer("1.2.3-beta", than: "1.2.3"))
    }
}
