@testable import MacPulse

enum PowerMonitorTests {
    static let tests: [MacPulseTestCase] = [
        MacPulseTestCase("Power monitor reads external input in watts", testExternalInput)
    ]

    static func testExternalInput() throws {
        let properties: [String: Any] = [
            "PowerTelemetryData": ["SystemPowerIn": 7_184],
            "PowerDistribution": ["IPDInputPower": 89_200],
            "Voltage": 12_449,
            "Amperage": 5_474
        ]
        try expectEqual(PowerMonitor.externalInputWatts(in: properties), 7.184)
        try expectEqual(PowerMonitor.externalInputWatts(in: ["PowerDistribution": ["IPDInputPower": 89_200]]), nil)
        try expectEqual(PowerMonitor.externalInputWatts(in: ["PowerTelemetryData": ["SystemPowerIn": 0]]), nil)
    }
}
