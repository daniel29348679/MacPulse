@testable import MacPulse

enum PowerMonitorTests {
    static let tests: [MacPulseTestCase] = [
        MacPulseTestCase("Power monitor reads external input in watts", testExternalInput)
    ]

    static func testExternalInput() throws {
        let properties: [String: Any] = [
            "PowerDistribution": ["IPDInputPower": 89_200],
            "Voltage": 12_449,
            "Amperage": 5_474
        ]
        try expectEqual(PowerMonitor.externalInputWatts(in: properties), 89.2)
        try expectEqual(PowerMonitor.externalInputWatts(in: ["Voltage": 12_449, "Amperage": 5_474]), nil)
        try expectEqual(PowerMonitor.externalInputWatts(in: ["PowerDistribution": ["IPDInputPower": 0]]), nil)
    }
}
