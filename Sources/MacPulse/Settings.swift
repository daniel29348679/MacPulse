import Foundation

/// 全域偏好設定，持久化到 UserDefaults。
final class Settings {
    static let shared = Settings()

    private enum Keys {
        static let updateInterval = "macpulse.updateInterval"
    }

    static let allowedIntervals: [TimeInterval] = [1.0, 1.5, 2.0, 3.0, 5.0]
    static let defaultInterval: TimeInterval = 1.5

    /// 採樣間隔（秒）。寫入時自動廣播 `intervalDidChange` 通知。
    var updateInterval: TimeInterval {
        get {
            let stored = UserDefaults.standard.double(forKey: Keys.updateInterval)
            return Self.allowedIntervals.contains(stored) ? stored : Self.defaultInterval
        }
        set {
            guard Self.allowedIntervals.contains(newValue) else { return }
            UserDefaults.standard.set(newValue, forKey: Keys.updateInterval)
            NotificationCenter.default.post(name: .macPulseIntervalChanged, object: nil)
        }
    }
}

extension Notification.Name {
    static let macPulseIntervalChanged = Notification.Name("macpulse.intervalChanged")
}
