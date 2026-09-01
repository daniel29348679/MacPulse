import Foundation
@testable import MacPulse

enum ProcessNavigationStateTests {
    static let tests: [MacPulseTestCase] = [
        MacPulseTestCase("Process navigation pushes and returns through pages", testPushAndBack),
        MacPulseTestCase("Process navigation ignores duplicate destination", testDuplicatePush),
        MacPulseTestCase("Process navigation reset clears resource route", testReset),
        MacPulseTestCase("Process entry identity survives metrics update and rejects PID reuse", testStableEntryIdentity)
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

    private static func group(_ entry: ProcessMonitor.Entry) -> ProcessMonitor.Group {
        .init(name: entry.name,
              totalCpuPercent: entry.cpuPercent,
              totalMemoryBytes: entry.memoryBytes,
              entries: [entry])
    }

    static func testPushAndBack() throws {
        let process = entry(pid: 42, identity: identity(1), cpu: 10, memory: 100)
        var state = ProcessNavigationState()
        try expect(state.isAtOverview)
        try expect(state.push(.list(.cpu)))
        try expect(state.push(.group(.cpu, name: "worker")))
        try expect(state.push(.entry(.cpu, groupName: "worker", id: ProcessEntryID(process))))
        try expectEqual(state.path.count, 3)

        _ = state.goBack()
        try expectEqual(state.current, .group(.cpu, name: "worker"))
        _ = state.goBack()
        try expectEqual(state.current, .list(.cpu))
        _ = state.goBack()
        try expect(state.isAtOverview)
    }

    static func testDuplicatePush() throws {
        var state = ProcessNavigationState()
        try expect(state.push(.list(.memory)))
        try expect(!state.push(.list(.memory)))
        try expectEqual(state.path.count, 1)
    }

    static func testReset() throws {
        var state = ProcessNavigationState()
        _ = state.push(.list(.memory))
        _ = state.push(.group(.memory, name: "worker"))
        state.reset()
        try expect(state.isAtOverview)
        try expectEqual(state.path.count, 0)
    }

    static func testStableEntryIdentity() throws {
        let originalIdentity = identity(10)
        let original = entry(pid: 42, identity: originalIdentity, cpu: 1, memory: 100)
        let id = ProcessEntryID(original)

        let updated = entry(pid: 42, identity: originalIdentity, cpu: 9, memory: 900)
        let resolved = id.resolve(in: [group(updated)], groupName: "worker")
        try expectEqual(resolved?.cpuPercent, 9)
        try expectEqual(resolved?.memoryBytes, 900)

        let reusedPID = entry(pid: 42, identity: identity(99), cpu: 50, memory: 5_000)
        try expect(id.resolve(in: [group(reusedPID)], groupName: "worker") == nil,
                   "a reused PID must not be rebound to the open process page")
    }
}
