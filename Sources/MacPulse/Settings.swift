import Foundation

enum Metric: String, CaseIterable, Codable {
    case cpu, memory, network, disk, temperature, power

    var displayName: String {
        switch self {
        case .cpu:         return "CPU"
        case .memory:      return "Memory"
        case .network:     return "Network"
        case .disk:        return "Disk"
        case .temperature: return "Temperature"
        case .power:       return "Power"
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
        case .power:       return "bolt.fill"
        }
    }
}

/// 全域偏好設定，持久化到 UserDefaults。
final class Settings {
    static let shared = Settings()

    private let defaults = UserDefaults.standard

    private enum Keys {
        static let updateInterval     = "macpulse.updateInterval"
        static let sparklineWindow    = "macpulse.sparkline.window"    // seconds
        static let menuBarVisible     = "macpulse.menuBar.visible"     // [Metric.rawValue]
        static let popoverVisible     = "macpulse.popover.visible"     // [Metric.rawValue]
    }

    static let allowedIntervals: [TimeInterval] = [0.5, 1.0, 3.0, 5.0, 10.0]
    static let defaultInterval: TimeInterval = 1.0

    static let allowedSparklineWindows: [TimeInterval] = [30, 60, 120, 300, 600]
    static let defaultSparklineWindow: TimeInterval = 60

    /// 給 UI 用的字串標籤（整數秒不顯示小數）
    static func intervalLabel(_ interval: TimeInterval) -> String {
        if interval.truncatingRemainder(dividingBy: 1) == 0 {
            return "\(Int(interval))s"
        }
        return String(format: "%.1fs", interval)
    }

    static func sparklineWindowLabel(_ seconds: TimeInterval) -> String {
        if seconds < 60 { return "\(Int(seconds))s" }
        return "\(Int(seconds) / 60)m"
    }

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

    /// 折線圖時間長度（秒）— sparkline capacity = ceil(window / updateInterval)
    var sparklineWindowSeconds: TimeInterval {
        get {
            let stored = defaults.double(forKey: Keys.sparklineWindow)
            return Self.allowedSparklineWindows.contains(stored) ? stored : Self.defaultSparklineWindow
        }
        set {
            guard Self.allowedSparklineWindows.contains(newValue) else { return }
            defaults.set(newValue, forKey: Keys.sparklineWindow)
            NotificationCenter.default.post(name: .macPulseSettingsChanged, object: nil)
        }
    }

    /// 依目前 updateInterval / sparklineWindowSeconds 計算 buffer 容量
    var sparklineCapacity: Int {
        let interval = max(updateInterval, 0.001)
        return max(2, Int(ceil(sparklineWindowSeconds / interval)))
    }

    /// 在選單列要顯示哪些指標
    var menuBarMetrics: Set<Metric> {
        get { readMetrics(key: Keys.menuBarVisible, default: [.cpu, .memory, .network, .power]) }
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
