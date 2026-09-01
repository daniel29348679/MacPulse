import Foundation
@testable import MacPulse

enum ProcessNavigationStateTests {
    static let tests: [MacPulseTestCase] = [
        MacPulseTestCase("Process navigation pushes and returns through pages", testPushAndBack),
        MacPulseTestCase("Process navigation ignores duplicate destination", testDuplicatePush),
        MacPulseTestCase("Process navigation reset clears route", testReset),
        MacPulseTestCase("Process entry identity survives metrics update and rejects PID reuse", testStableEntryIdentity),
        MacPulseTestCase("Process sorting supports CPU RAM disk and name", testSorting)
    ]

    private static func identity(_ seconds: Int64) -> ProcessMonitor.ProcessIdentity {
        .init(startTimeSeconds: seconds, startTimeMicroseconds: 0, uid: 501)
    }

    private static func entry(pid: Int32,
                              identity: ProcessMonitor.ProcessIdentity,
                              cpu: Double,
                              memory: UInt64) -> ProcessMonitor.Entry {
        .init(pid: pid,
              name: "worker",
              command: "/usr/bin/worker",
              cpuPercent: cpu,
              memoryBytes: memory,
              identity: identity)
    }

    static func testPushAndBack() throws {
        let process = entry(pid: 42, identity: identity(1), cpu: 10, memory: 100)
        var state = ProcessNavigationState()
        try expect(state.isAtOverview)
        try expect(state.push(.processes))
        try expect(state.push(.entry(id: ProcessEntryID(process), metric: .cpu)))
        try expectEqual(state.path.count, 2)

        _ = state.goBack()
        try expectEqual(state.current, .processes)
        _ = state.goBack()
        try expect(state.isAtOverview)
    }

    static func testDuplicatePush() throws {
        var state = ProcessNavigationState()
        try expect(state.push(.processes))
        try expect(!state.push(.processes))
        try expectEqual(state.path.count, 1)
    }

    static func testReset() throws {
        var state = ProcessNavigationState()
        _ = state.push(.processes)
        state.reset()
        try expect(state.isAtOverview)
        try expectEqual(state.path.count, 0)
    }

    static func testStableEntryIdentity() throws {
        let originalIdentity = identity(10)
        let original = entry(pid: 42, identity: originalIdentity, cpu: 1, memory: 100)
        let id = ProcessEntryID(original)

        let updated = entry(pid: 42, identity: originalIdentity, cpu: 9, memory: 900)
        let resolved = id.resolve(in: [updated])
        try expectEqual(resolved?.cpuPercent, 9)
        try expectEqual(resolved?.memoryBytes, 900)

        let reusedPID = entry(pid: 42, identity: identity(99), cpu: 50, memory: 5_000)
        try expect(id.resolve(in: [reusedPID]) == nil,
                   "a reused PID must not be rebound to the open process page")
    }

    static func testSorting() throws {
        let first = ProcessMonitor.Entry(pid: 1,
                                         name: "Zulu",
                                         command: "/bin/zulu",
                                         cpuPercent: 2,
                                         memoryBytes: 300,
                                         diskBytesPerSecond: 40,
                                         identity: identity(1))
        let second = ProcessMonitor.Entry(pid: 2,
                                          name: "Alpha",
                                          command: "/bin/alpha",
                                          cpuPercent: 8,
                                          memoryBytes: 100,
                                          diskBytesPerSecond: 70,
                                          identity: identity(2))
        let values = [first, second]
        try expectEqual(ProcessSortMetric.name.sorted(values, ascending: true).map(\.pid), [2, 1])
        try expectEqual(ProcessSortMetric.cpu.sorted(values, ascending: false).map(\.pid), [2, 1])
        try expectEqual(ProcessSortMetric.memory.sorted(values, ascending: false).map(\.pid), [1, 2])
        try expectEqual(ProcessSortMetric.disk.sorted(values, ascending: false).map(\.pid), [2, 1])
    }
}
