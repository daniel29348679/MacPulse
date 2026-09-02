import Foundation
@testable import MacPulse

enum SingleInstanceLockTests {
    static let tests: [MacPulseTestCase] = [
        MacPulseTestCase("Single instance lock rejects a second owner and recovers", testExclusiveLock)
    ]

    static func testExclusiveLock() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacPulseTests.\(UUID().uuidString).lock")
        defer { try? FileManager.default.removeItem(at: url) }

        var first: SingleInstanceLock? = SingleInstanceLock(lockFileURL: url)
        try expect(first != nil, "first owner failed to acquire lock")
        try expect(SingleInstanceLock(lockFileURL: url) == nil,
                   "second owner unexpectedly acquired lock")

        first = nil
        try expect(SingleInstanceLock(lockFileURL: url) != nil,
                   "lock did not release after its owner exited")
    }
}
