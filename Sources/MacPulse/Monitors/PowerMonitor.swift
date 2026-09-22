import Foundation
import IOKit
import IOKit.ps

/// Reads external input and battery discharge from `AppleSmartBattery` in IORegistry.
///
/// On external power, `PowerTelemetryData.SystemPowerIn` reports measured
/// input power in milliwatts. On battery, `Voltage` is in millivolts and `Amperage` in
/// milliamps; their product gives battery discharge in microwatts.
///
/// 充電百分比走 `IOPSCopyPowerSourcesInfo`（IOPS）：它對外保證
/// `kIOPSCurrentCapacityKey` / `kIOPSMaxCapacityKey` 一律是 0–100 規範化值，
/// 跟系統選單列、Battery preference pane 顯示一致。直接用 AppleSmartBattery
/// 的 `CurrentCapacity` / `MaxCapacity` 在 Apple Silicon 上是 mAh 而非百分比，
/// 不同 macOS 版本回傳的單位也不一致（有時是 health %），算出來會偏差。
final class PowerMonitor {

    enum State {
        /// Plugged in and battery is filling up.
        case charging
        /// Plugged in but battery is full (or system is bypassing battery).
        case ac
        /// On battery — drawing from the cells.
        case discharging
        /// Desktop Mac, no battery present.
        case unavailable
    }

    struct Sample {
        let state: State
        /// External input on AC; battery discharge when unplugged. Nil if unavailable.
        let watts: Double?
        /// Battery charge level, 0–100. nil when no battery.
        let percent: Int?
    }

    func sample() -> Sample {
        // 百分比走 IOPS — 跨機型一致、與系統顯示同源
        let percent = Self.batteryPercent()

        let entry = IOServiceGetMatchingService(kIOMainPortDefault,
                                                IOServiceMatching("AppleSmartBattery"))
        guard entry != 0 else {
            // 桌機（沒電池）IOPS 也會回 nil — 視為 unavailable
            return Sample(state: .unavailable, watts: nil, percent: percent)
        }
        defer { IOObjectRelease(entry) }

        var unmanaged: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(entry, &unmanaged, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let dict = unmanaged?.takeRetainedValue() as? [String: Any] else {
            return Sample(state: .unavailable, watts: nil, percent: percent)
        }

        let isCharging = (dict["IsCharging"] as? Bool) ?? false
        let externalConnected = (dict["ExternalConnected"] as? Bool) ?? false
        if externalConnected {
            return Sample(state: isCharging ? .charging : .ac,
                          watts: Self.externalInputWatts(in: dict),
                          percent: percent)
        }

        guard let voltageMV = dict["Voltage"] as? Int,
              let amperageMA = dict["Amperage"] as? Int else {
            return Sample(state: .unavailable, watts: nil, percent: percent)
        }
        // mV * mA = µW; the sign convention varies by Mac generation.
        let watts = abs(Double(voltageMV) * Double(amperageMA)) / 1_000_000.0
        return Sample(state: .discharging, watts: watts, percent: percent)
    }

    static func externalInputWatts(in properties: [String: Any]) -> Double? {
        guard let telemetry = properties["PowerTelemetryData"] as? [String: Any],
              let milliwatts = telemetry["SystemPowerIn"] as? Int,
              milliwatts > 0 else { return nil }
        return Double(milliwatts) / 1_000.0
    }

    /// 從 IOPSCopyPowerSourcesInfo 取得內建電池的 0–100 百分比；桌機無電池回 nil。
    private static func batteryPercent() -> Int? {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] else {
            return nil
        }
        for source in sources {
            guard let desc = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue()
                    as? [String: Any] else { continue }
            // 只認內建電池 — 排除 UPS / 藍牙鍵盤之類附加電源
            if let type = desc[kIOPSTypeKey as String] as? String,
               type != kIOPSInternalBatteryType as String {
                continue
            }
            guard let cur = desc[kIOPSCurrentCapacityKey as String] as? Int,
                  let max = desc[kIOPSMaxCapacityKey as String] as? Int,
                  max > 0 else { continue }
            return Int((Double(cur) / Double(max) * 100).rounded())
        }
        return nil
    }
}
