import AppKit
@testable import MacPulse

enum StatusBarFormattingTests {
    static let tests: [MacPulseTestCase] = [
        MacPulseTestCase("Status bar percentage stays within two digits", testPercentageFormatting),
        MacPulseTestCase("Status bar CPU and RAM use compact symbols", testMetricSymbols)
    ]

    static func testPercentageFormatting() throws {
        try expectEqual(StatusBarController.fixedWidthPercent(9), "\u{2007}9%")
        try expectEqual(StatusBarController.fixedWidthPercent(10), "10%")
        try expectEqual(StatusBarController.fixedWidthPercent(99), "99%")
        try expectEqual(StatusBarController.fixedWidthPercent(100), "99%")
    }

    static func testMetricSymbols() throws {
        let font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        let symbolic = StatusBarController.attributedStatusLine(
            "\(StatusBarController.cpuSymbolMarker) 42%  \(StatusBarController.memorySymbolMarker) 68%",
            font: font
        )
        let textual = StatusBarController.attributedStatusLine("CPU 42%  RAM 68%", font: font)

        try expectEqual(symbolic.string, "\u{FFFC} 42%  \u{FFFC} 68%")
        try expect(symbolic.attribute(.attachment, at: 0, effectiveRange: nil) is NSTextAttachment)
        let ramLocation = (symbolic.string as NSString).range(of: "\u{FFFC}",
                                                               options: [],
                                                               range: NSRange(location: 1,
                                                                              length: symbolic.length - 1)).location
        try expect(symbolic.attribute(.attachment, at: ramLocation, effectiveRange: nil) is NSTextAttachment)
        try expect(symbolic.size().width < textual.size().width,
                   "symbol labels should be narrower than CPU and RAM text")
    }
}
