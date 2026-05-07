import Foundation
import IOKit

/// Reads battery power flow from `AppleSmartBattery` in IORegistry.
///
/// `Voltage` is in millivolts, `Amperage` is in milliamps and signed
/// (positive = charging on most Macs, negative = discharging — but sign
/// conventions vary per generation, so we always report `|V * I|` and
/// rely on `IsCharging` / `ExternalConnected` to label the direction).
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
        let entry = IOServiceGetMatchingService(kIOMainPortDefault,
                                                IOServiceMatching("AppleSmartBattery"))
        guard entry != 0 else {
            return Sample(state: .unavailable, watts: nil, percent: nil)
        }
        defer { IOObjectRelease(entry) }

        var unmanaged: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(entry, &unmanaged, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let dict = unmanaged?.takeRetainedValue() as? [String: Any] else {
            return Sample(state: .unavailable, watts: nil, percent: nil)
        }

        let voltageMV = (dict["Voltage"] as? Int) ?? 0
        let amperageMA = (dict["Amperage"] as? Int) ?? 0
        let isCharging = (dict["IsCharging"] as? Bool) ?? false
        let externalConnected = (dict["ExternalConnected"] as? Bool) ?? false
        let currentCapacity = dict["CurrentCapacity"] as? Int
        let maxCapacity = dict["MaxCapacity"] as? Int

        // mV * mA = µW → divide by 1e6 for W. abs() because sign convention
        // differs across Mac generations and we display direction via state.
        let watts = abs(Double(voltageMV) * Double(amperageMA)) / 1_000_000.0

        let state: State = {
            if isCharging { return .charging }
            if externalConnected { return .ac }
            return .discharging
        }()

        let percent: Int? = {
            guard let cur = currentCapacity, let max = maxCapacity, max > 0 else { return nil }
            return Int((Double(cur) / Double(max) * 100).rounded())
        }()

        return Sample(state: state, watts: watts, percent: percent)
    }
}
