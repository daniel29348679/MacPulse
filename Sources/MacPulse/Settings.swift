import Foundation

enum Metric: String, CaseIterable, Codable {
    case cpu, memory, network, disk, temperature

    var displayName: String {
        switch self {
        case .cpu:         return "CPU"
        case .memory:      return "Memory"
        case .network:     return "Network"
        case .disk:        return "Disk"
        case .temperature: return "Temperature"
        }
    }

    /// SF Symbol 名稱（13.0+ 都支援）
    var symbolName: String {
        switch self {
        case .cpu:         return "cpu"
        case .memory:      return "memorychip"
        case .network:     return "network"
        case .disk:        return "internaldrive"
        case .temperature: return "thermometer.medium"
        }
    }
}

/// 全域偏好設定，持久化到 UserDefaults。
final class Settings {
    static let shared = Settings()

    private let defaults = UserDefaults.standard

    private enum Keys {
        static let updateInterval     = "macpulse.updateInterval"
        static let menuBarVisible     = "macpulse.menuBar.visible"     // [Metric.rawValue]
        static let popoverVisible     = "macpulse.popover.visible"     // [Metric.rawValue]
    }

    static let allowedIntervals: [TimeInterval] = [1.0, 1.5, 2.0, 3.0, 5.0]
    static let defaultInterval: TimeInterval = 1.5

    /// 採樣間隔（秒）
    var updateInterval: TimeInterval {
        get {
            let stored = defaults.double(forKey: Keys.updateInterval)
            return Self.allowedIntervals.contains(stored) ? stored : Self.defaultInterval
        }
        set {
            guard Self.allowedIntervals.contains(newValue) else { return }
            defaults.set(newValue, forKey: Keys.updateInterval)
            NotificationCenter.default.post(name: .macPulseSettingsChanged, object: nil)
        }
    }

    /// 在選單列要顯示哪些指標
    var menuBarMetrics: Set<Metric> {
        get { readMetrics(key: Keys.menuBarVisible, default: [.cpu, .memory, .network]) }
        set {
            writeMetrics(newValue, key: Keys.menuBarVisible)
            NotificationCenter.default.post(name: .macPulseSettingsChanged, object: nil)
        }
    }

    /// 在 popover 詳細頁要顯示哪些指標
    var popoverMetrics: Set<Metric> {
        get { readMetrics(key: Keys.popoverVisible, default: Set(Metric.allCases)) }
        set {
            writeMetrics(newValue, key: Keys.popoverVisible)
            NotificationCenter.default.post(name: .macPulseSettingsChanged, object: nil)
        }
    }

    func toggleMenuBar(_ metric: Metric) {
        var s = menuBarMetrics
        if s.contains(metric) { s.remove(metric) } else { s.insert(metric) }
        menuBarMetrics = s
    }

    func togglePopover(_ metric: Metric) {
        var s = popoverMetrics
        if s.contains(metric) { s.remove(metric) } else { s.insert(metric) }
        popoverMetrics = s
    }

    // MARK: - Storage

    private func readMetrics(key: String, default fallback: Set<Metric>) -> Set<Metric> {
        guard let raw = defaults.array(forKey: key) as? [String] else { return fallback }
        return Set(raw.compactMap(Metric.init(rawValue:)))
    }

    private func writeMetrics(_ value: Set<Metric>, key: String) {
        defaults.set(value.map(\.rawValue), forKey: key)
    }
}

extension Notification.Name {
    /// 任何設定變動都廣播這個通知 — controller 訂閱以便重繪／重排 timer。
    static let macPulseSettingsChanged = Notification.Name("macpulse.settingsChanged")

    /// 向後相容：舊的 interval 變更通知改成 alias
    static let macPulseIntervalChanged = Notification.Name("macpulse.settingsChanged")
}
