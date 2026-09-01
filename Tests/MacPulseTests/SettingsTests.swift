import Foundation
@testable import MacPulse

final class SettingsTests {
    static let tests: [MacPulseTestCase] = [
        MacPulseTestCase("Settings labels allowed values", testLabelsForAllowedValues),
        MacPulseTestCase("Settings rejects unsupported update intervals", testUpdateIntervalRejectsUnsupportedValues),
        MacPulseTestCase("Settings rejects unsupported sparkline windows", testSparklineWindowRejectsUnsupportedValues),
        MacPulseTestCase("Settings metric toggles round-trip", testMetricTogglesRoundTripThroughDefaults)
    ]

    private let suiteName: String
    private let defaults: UserDefaults
    private let settings: Settings

    init() {
        suiteName = "MacPulseTests.Settings.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        settings = Settings(defaults: defaults)
    }

    deinit {
        defaults.removePersistentDomain(forName: suiteName)
    }

    static func testLabelsForAllowedValues() throws {
        try expectEqual(Settings.intervalLabel(0.5), "0.5s")
        try expectEqual(Settings.intervalLabel(5.0), "5s")
        try expectEqual(Settings.sparklineWindowLabel(30), "30s")
        try expectEqual(Settings.sparklineWindowLabel(120), "2m")
    }

    static func testUpdateIntervalRejectsUnsupportedValues() throws {
        let suite = SettingsTests()
        try expectEqual(suite.settings.updateInterval, Settings.defaultInterval)

        suite.settings.updateInterval = 3.0
        try expectEqual(suite.settings.updateInterval, 3.0)

        suite.settings.updateInterval = 2.0
        try expectEqual(suite.settings.updateInterval, 3.0)
    }

    static func testSparklineWindowRejectsUnsupportedValues() throws {
        let suite = SettingsTests()
        try expectEqual(suite.settings.sparklineWindowSeconds, Settings.defaultSparklineWindow)

        suite.settings.sparklineWindowSeconds = 120
        try expectEqual(suite.settings.sparklineWindowSeconds, 120)

        suite.settings.sparklineWindowSeconds = 90
        try expectEqual(suite.settings.sparklineWindowSeconds, 120)
    }

    static func testMetricTogglesRoundTripThroughDefaults() throws {
        let suite = SettingsTests()

        suite.settings.menuBarMetrics = [.cpu]
        suite.settings.toggleMenuBar(.gpu)
        try expectEqual(suite.settings.menuBarMetrics, Set([Metric.cpu, .gpu]))

        suite.settings.toggleMenuBar(.cpu)
        try expectEqual(suite.settings.menuBarMetrics, Set([Metric.gpu]))

        suite.settings.popoverMetrics = [.memory]
        suite.settings.togglePopover(.disk)
        try expectEqual(suite.settings.popoverMetrics, Set([Metric.memory, .disk]))
    }
}
