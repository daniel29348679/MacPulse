import Darwin
import Foundation
import IOKit

// MARK: - Private IOHIDEventSystem dynamic bridge
//
// On Apple Silicon, no public API exposes CPU/GPU temperature. The widely-used
// trick (Stats, iStats Menus, etc.) is the IOHIDEventSystemClient family — it's
// in IOKit.framework but not in the public headers. We resolve them at runtime
// via dlsym and call them through @convention(c) function pointers.
//
// Treating the returned object as a CF opaque pointer (OpaquePointer) is the
// crucial bit; using Swift `AnyObject` here would crash because these CF types
// are not toll-free bridged to NSObject.

private typealias HIDClient = OpaquePointer
private typealias HIDService = OpaquePointer
private typealias HIDEvent = OpaquePointer

private typealias FnCreate        = @convention(c) (CFAllocator?) -> HIDClient?
private typealias FnSetMatching   = @convention(c) (HIDClient, CFDictionary?) -> Int32
private typealias FnCopyServices  = @convention(c) (HIDClient) -> Unmanaged<CFArray>?
private typealias FnCopyEvent     = @convention(c) (HIDService, Int64, Int32, Int64) -> Unmanaged<CFTypeRef>?
private typealias FnCopyProperty  = @convention(c) (HIDService, CFString) -> Unmanaged<CFTypeRef>?
private typealias FnGetFloatValue = @convention(c) (HIDEvent, Int32) -> Double

private struct IOHIDFns {
    let create: FnCreate
    let setMatching: FnSetMatching
    let copyServices: FnCopyServices
    let copyEvent: FnCopyEvent
    let copyProperty: FnCopyProperty
    let getFloatValue: FnGetFloatValue

    static let resolved: IOHIDFns? = {
        // Symbols live in the already-loaded IOKit.framework; passing nil to
        // dlopen searches the global symbol space.
        guard let handle = dlopen(nil, RTLD_LAZY) else { return nil }
        func sym<T>(_ name: String, as: T.Type) -> T? {
            guard let raw = dlsym(handle, name) else { return nil }
            return unsafeBitCast(raw, to: T.self)
        }
        guard
            let create        = sym("IOHIDEventSystemClientCreate",    as: FnCreate.self),
            let setMatching   = sym("IOHIDEventSystemClientSetMatching", as: FnSetMatching.self),
            let copyServices  = sym("IOHIDEventSystemClientCopyServices", as: FnCopyServices.self),
            let copyEvent     = sym("IOHIDServiceClientCopyEvent",     as: FnCopyEvent.self),
            let copyProperty  = sym("IOHIDServiceClientCopyProperty",  as: FnCopyProperty.self),
            let getFloatValue = sym("IOHIDEventGetFloatValue",         as: FnGetFloatValue.self)
        else {
            return nil
        }
        return IOHIDFns(
            create: create,
            setMatching: setMatching,
            copyServices: copyServices,
            copyEvent: copyEvent,
            copyProperty: copyProperty,
            getFloatValue: getFloatValue
        )
    }()
}

private let kIOHIDEventTypeTemperature: Int64 = 15
// IOHIDEventFieldBase(type) == type << 16
private let kIOHIDEventFieldTemperatureLevel: Int32 = Int32(15 << 16)

struct TemperatureReading {
    let name: String
    let celsius: Double
}

enum TemperatureSensors {

    /// 共享的 client。建立一次後緩存，重複用。
    private static let client: HIDClient? = {
        guard let fns = IOHIDFns.resolved else { return nil }
        guard let client = fns.create(kCFAllocatorDefault) else { return nil }
        let match: [String: Any] = [
            "PrimaryUsagePage": 0xff00,  // kHIDPage_AppleVendor
            "PrimaryUsage":     0x0005   // kHIDUsage_AppleVendor_TemperatureSensor
        ]
        _ = fns.setMatching(client, match as CFDictionary)
        return client
    }()

    static func read() -> [TemperatureReading] {
        guard let fns = IOHIDFns.resolved, let client else { return [] }
        guard let unmanagedArray = fns.copyServices(client) else { return [] }
        let services = unmanagedArray.takeRetainedValue() as Array

        var readings: [TemperatureReading] = []
        readings.reserveCapacity(services.count)

        for raw in services {
            let service: HIDService = unsafeBitCast(raw as AnyObject, to: HIDService.self)

            guard let nameUnmanaged = fns.copyProperty(service, "Product" as CFString) else { continue }
            let nameAny = nameUnmanaged.takeRetainedValue()
            guard let name = nameAny as? String else { continue }

            guard let unmanagedEvent = fns.copyEvent(service, kIOHIDEventTypeTemperature, 0, 0)
            else { continue }
            let eventObj = unmanagedEvent.takeRetainedValue()
            let event: HIDEvent = unsafeBitCast(eventObj, to: HIDEvent.self)

            let value = fns.getFloatValue(event, kIOHIDEventFieldTemperatureLevel)
            _ = eventObj
            guard value > 0, value < 200 else { continue }
            readings.append(TemperatureReading(name: name, celsius: value))
        }
        return readings
    }

    /// 估算 CPU 溫度：找 die / cluster 感測器，取最大值。
    /// - Apple Silicon (M-series)：`PMU tdie*`、`pACC MTR Temp`、`eACC MTR Temp`
    /// - Intel：`TC0P` / `TC0H` / `TC0E` / `TC0F`、或名稱含 `CPU`
    /// - 排除電池、NAND、GPU、ANE 等明顯不屬於 CPU 的感測器
    /// 拿不到任何讀數時回傳 nil — 呼叫端應退回 ProcessInfo.thermalState。
    static func cpuCelsius() -> Double? {
        let all = read()
        guard !all.isEmpty else { return nil }

        let cpuPatterns = ["PMU tdie", "pACC MTR", "eACC MTR", "TC0P", "TC0E", "TC0F", "TC0H", "CPU"]
        let exclude = ["tcal", "battery", "NAND", "GPU", "ANE", "ISP", "SOC", "PMP"]

        let cpuReadings = all.filter { reading in
            let matchesCPU = cpuPatterns.contains { reading.name.contains($0) }
            let isExcluded = exclude.contains { reading.name.contains($0) }
            return matchesCPU && !isExcluded
        }

        let candidates = cpuReadings.isEmpty ? all : cpuReadings
        return candidates.map(\.celsius).max()
    }
}
