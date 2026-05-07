import Foundation
import IOKit

final class DiskMonitor {
    struct Sample {
        let readBytesPerSec: Double
        let writeBytesPerSec: Double
    }

    private var previousRead: UInt64 = 0
    private var previousWrite: UInt64 = 0
    private var previousTime: Date?

    func sample() -> Sample {
        let (totalRead, totalWrite) = readDriveCounters()
        let now = Date()

        defer {
            previousRead = totalRead
            previousWrite = totalWrite
            previousTime = now
        }

        guard let last = previousTime else {
            return Sample(readBytesPerSec: 0, writeBytesPerSec: 0)
        }

        let elapsed = now.timeIntervalSince(last)
        guard elapsed > 0 else {
            return Sample(readBytesPerSec: 0, writeBytesPerSec: 0)
        }

        let readDelta  = totalRead  >= previousRead  ? totalRead  - previousRead  : 0
        let writeDelta = totalWrite >= previousWrite ? totalWrite - previousWrite : 0

        return Sample(
            readBytesPerSec:  Double(readDelta)  / elapsed,
            writeBytesPerSec: Double(writeDelta) / elapsed
        )
    }

    private func readDriveCounters() -> (UInt64, UInt64) {
        guard let matching = IOServiceMatching("IOBlockStorageDriver") else {
            return (0, 0)
        }

        var iterator: io_iterator_t = 0
        let result = IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator)
        guard result == KERN_SUCCESS else {
            return (0, 0)
        }
        defer { IOObjectRelease(iterator) }

        var totalRead: UInt64 = 0
        var totalWrite: UInt64 = 0

        var drive = IOIteratorNext(iterator)
        while drive != 0 {
            defer {
                IOObjectRelease(drive)
                drive = IOIteratorNext(iterator)
            }

            var unmanagedProps: Unmanaged<CFMutableDictionary>?
            guard IORegistryEntryCreateCFProperties(drive, &unmanagedProps, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                  let props = unmanagedProps?.takeRetainedValue() as? [String: Any],
                  let stats = props["Statistics"] as? [String: Any]
            else {
                continue
            }

            if let r = stats["Bytes (Read)"] as? NSNumber {
                totalRead &+= r.uint64Value
            }
            if let w = stats["Bytes (Write)"] as? NSNumber {
                totalWrite &+= w.uint64Value
            }
        }

        return (totalRead, totalWrite)
    }
}
