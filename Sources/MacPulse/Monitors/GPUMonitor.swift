import Foundation
import IOKit

final class GPUMonitor {
    struct Sample {
        let utilizationPercent: Double?
        let rendererPercent: Double?
        let tilerPercent: Double?
        let usedMemoryBytes: UInt64?
        let modelName: String?
        let coreCount: Int?

        var hasStats: Bool {
            utilizationPercent != nil ||
            rendererPercent != nil ||
            tilerPercent != nil ||
            usedMemoryBytes != nil
        }
    }

    func sample() -> Sample {
        var iterator: io_iterator_t = 0
        let result = IOServiceGetMatchingServices(
            kIOMainPortDefault,
            IOServiceMatching("IOAccelerator"),
            &iterator
        )
        guard result == KERN_SUCCESS else { return Self.unavailable }
        defer { IOObjectRelease(iterator) }

        var utilizationValues: [Double] = []
        var rendererValues: [Double] = []
        var tilerValues: [Double] = []
        var usedMemoryBytes: UInt64 = 0
        var foundUsedMemory = false
        var modelName: String?
        var coreCount: Int?

        while true {
            let service = IOIteratorNext(iterator)
            guard service != 0 else { break }
            defer { IOObjectRelease(service) }

            if modelName == nil {
                modelName = Self.stringProperty(service, key: "model")
            }
            if coreCount == nil {
                coreCount = Self.intProperty(service, key: "gpu-core-count")
            }

            guard let stats = Self.dictionaryProperty(service, key: "PerformanceStatistics") else {
                continue
            }

            if let value = Self.double(stats["Device Utilization %"]) {
                utilizationValues.append(value)
            }
            if let value = Self.double(stats["Renderer Utilization %"]) {
                rendererValues.append(value)
            }
            if let value = Self.double(stats["Tiler Utilization %"]) {
                tilerValues.append(value)
            }
            if let bytes = Self.uint64(stats["In use system memory"]) {
                usedMemoryBytes += bytes
                foundUsedMemory = true
            }
        }

        return Sample(
            utilizationPercent: utilizationValues.max().map(Self.clampedPercent),
            rendererPercent: rendererValues.max().map(Self.clampedPercent),
            tilerPercent: tilerValues.max().map(Self.clampedPercent),
            usedMemoryBytes: foundUsedMemory ? usedMemoryBytes : nil,
            modelName: modelName,
            coreCount: coreCount
        )
    }

    private static let unavailable = Sample(
        utilizationPercent: nil,
        rendererPercent: nil,
        tilerPercent: nil,
        usedMemoryBytes: nil,
        modelName: nil,
        coreCount: nil
    )

    private static func dictionaryProperty(_ service: io_object_t, key: String) -> [String: Any]? {
        guard let value = IORegistryEntryCreateCFProperty(
            service,
            key as CFString,
            kCFAllocatorDefault,
            0
        )?.takeRetainedValue() else {
            return nil
        }
        return value as? [String: Any]
    }

    private static func stringProperty(_ service: io_object_t, key: String) -> String? {
        guard let value = IORegistryEntryCreateCFProperty(
            service,
            key as CFString,
            kCFAllocatorDefault,
            0
        )?.takeRetainedValue() else {
            return nil
        }

        if let string = value as? String {
            return string
        }
        if let data = value as? Data {
            return String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .controlCharacters)
        }
        return nil
    }

    private static func intProperty(_ service: io_object_t, key: String) -> Int? {
        guard let value = IORegistryEntryCreateCFProperty(
            service,
            key as CFString,
            kCFAllocatorDefault,
            0
        )?.takeRetainedValue() else {
            return nil
        }
        return int(value)
    }

    private static func double(_ value: Any?) -> Double? {
        switch value {
        case let number as NSNumber:
            return number.doubleValue
        case let value as Double:
            return value
        case let value as Int:
            return Double(value)
        case let value as UInt64:
            return Double(value)
        default:
            return nil
        }
    }

    private static func uint64(_ value: Any?) -> UInt64? {
        switch value {
        case let number as NSNumber:
            return number.uint64Value
        case let value as UInt64:
            return value
        case let value as Int where value >= 0:
            return UInt64(value)
        case let value as Double where value >= 0:
            return UInt64(value)
        default:
            return nil
        }
    }

    private static func int(_ value: Any?) -> Int? {
        switch value {
        case let number as NSNumber:
            return number.intValue
        case let value as Int:
            return value
        default:
            return nil
        }
    }

    private static func clampedPercent(_ value: Double) -> Double {
        min(max(value, 0), 100)
    }
}
