import AppKit
import Foundation

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

        /// 由 °C 推測等級。閾值參考 Apple Silicon 一般情境（大約值，不同晶片會有差距）。
        static func from(celsius: Double) -> Level {
            switch celsius {
            case ..<55:   return .nominal
            case ..<70:   return .fair
            case ..<85:   return .serious
            default:      return .critical
            }
        }
    }

    struct Sample {
        /// 直接讀到的 CPU 溫度（°C）；若 IOHID 沒回任何感測器則為 nil（退回 thermalState）
        let celsius: Double?
        let level: Level
    }

    func sample() -> Sample {
        if let temp = TemperatureSensors.cpuCelsius() {
            return Sample(celsius: temp, level: Level.from(celsius: temp))
        }
        // Fallback：拿不到就用 ProcessInfo 的 4 級熱壓力
        let level: Level
        switch ProcessInfo.processInfo.thermalState {
        case .nominal:  level = .nominal
        case .fair:     level = .fair
        case .serious:  level = .serious
        case .critical: level = .critical
        @unknown default: level = .nominal
        }
        return Sample(celsius: nil, level: level)
    }
}
