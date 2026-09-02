@testable import MacPulse

enum StatusBarFormattingTests {
    static let tests: [MacPulseTestCase] = [
        MacPulseTestCase("Status bar percentage stays within two digits", testPercentageFormatting)
    ]

    static func testPercentageFormatting() throws {
        try expectEqual(StatusBarController.fixedWidthPercent(9), "\u{2007}9%")
        try expectEqual(StatusBarController.fixedWidthPercent(10), "10%")
        try expectEqual(StatusBarController.fixedWidthPercent(99), "99%")
        try expectEqual(StatusBarController.fixedWidthPercent(100), "99%")
    }
}
