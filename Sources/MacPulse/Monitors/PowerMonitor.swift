import Foundation
import IOKit
import IOKit.ps

/// Reads battery power flow from `AppleSmartBattery` in IORegistry.
///
/// `Voltage` is in millivolts, `Amperage` is in milliamps and signed
/// (positive = charging on most Macs, negative = discharging — but sign
/// conventions vary per generation, so we always report `|V * I|` and
/// rely on `IsCharging` / `ExternalConnected` to label the direction).
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
        /// Always non-negative. nil when no battery is available.
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

        let voltageMV = dict["Voltage"] as? Int
        let amperageMA = dict["Amperage"] as? Int
        let isCharging = (dict["IsCharging"] as? Bool) ?? false
        let externalConnected = (dict["ExternalConnected"] as? Bool) ?? false

        guard let voltageMV, let amperageMA else {
            return Sample(state: externalConnected ? .ac : .unavailable, watts: nil, percent: percent)
        }

        // mV * mA = µW → divide by 1e6 for W. abs() because sign convention
        // differs across Mac generations and we display direction via state.
        let watts = abs(Double(voltageMV) * Double(amperageMA)) / 1_000_000.0

        let state: State = {
            if isCharging { return .charging }
            if externalConnected { return .ac }
            return .discharging
        }()

        return Sample(state: state, watts: watts, percent: percent)
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
