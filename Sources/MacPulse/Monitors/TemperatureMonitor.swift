import AppKit
import Foundation

/// macOS 沒有公開 API 可在 Apple Silicon 上讀取真實 ºC（SMC key 各代不同且不穩定）。
/// 我們改用 ProcessInfo.processInfo.thermalState — 這是 Apple 官方建議的「熱壓力」指標，
/// 共四級：nominal / fair / serious / critical。
final class TemperatureMonitor {
    enum Level: String {
        case nominal, fair, serious, critical

        var label: String {
            switch self {
            case .nominal:  return "Cool"
            case .fair:     return "Warm"
            case .serious:  return "Hot"
            case .critical: return "Critical"
            }
        }

        /// 給狀態列用的緊湊符號（emoji 在等寬字型下也能對齊）
        var compactSymbol: String {
            switch self {
            case .nominal:  return "❄"
            case .fair:     return "≈"
            case .serious:  return "▲"
            case .critical: return "⚠"
            }
        }

        var color: NSColor {
            switch self {
            case .nominal:  return .systemBlue
            case .fair:     return .systemGreen
            case .serious:  return .systemOrange
            case .critical: return .systemRed
            }
        }
    }

    struct Sample {
        let level: Level
    }

    func sample() -> Sample {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal:  return Sample(level: .nominal)
        case .fair:     return Sample(level: .fair)
        case .serious:  return Sample(level: .serious)
        case .critical: return Sample(level: .critical)
        @unknown default: return Sample(level: .nominal)
        }
    }
}
