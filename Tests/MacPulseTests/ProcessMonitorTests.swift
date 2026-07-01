import Foundation
@testable import MacPulse

enum ProcessMonitorTests {
    static let tests: [MacPulseTestCase] = [
        MacPulseTestCase("ProcessMonitor live sample includes own process", testLiveSampleIncludesOwnProcess),
        MacPulseTestCase("ProcessMonitor live sample measures busy process CPU", testLiveSampleMeasuresBusyProcessCPU),
        MacPulseTestCase("ProcessMonitor displayName uses binary basename", testDisplayNameUsesBinaryBaseName),
        MacPulseTestCase("ProcessMonitor displayName keeps kernel names", testDisplayNameKeepsKernelStyleNames),
        MacPulseTestCase("ProcessMonitor displayName adds interpreter script", testDisplayNameAddsScriptForInterpreters),
        MacPulseTestCase("ProcessMonitor displayName handles empty command", testDisplayNameHandlesEmptyCommand),
        MacPulseTestCase("ProcessMonitor computeEntries normalizes CPU and sorts", testComputeEntriesNormalizesAndSorts),
        MacPulseTestCase("ProcessMonitor computeEntries clamps cpu at 100", testComputeEntriesClampsCPUAtOneHundred),
        MacPulseTestCase("ProcessMonitor computeEntries zero on first tick", testComputeEntriesZeroOnFirstTick),
        MacPulseTestCase("ProcessMonitor computeEntries treats PID reuse as new process", testComputeEntriesPIDReuseGivesZero),
        MacPulseTestCase("ProcessMonitor computeEntries applies limit", testComputeEntriesAppliesLimit)
    ]

    static func testLiveSampleIncludesOwnProcess() throws {
        // 冒煙測試真正的 libproc 取樣路徑（共用 argv buffer + 命令列快取）：
        // 連取兩次，第二次同 pid 且同 identity 的項目會走快取，
        // 命令列必須跟第一次一致；且至少要有讀得到 argv 的項目。
        let monitor = ProcessMonitor()

        let first = monitor.sampleSync(limit: ProcessMonitor.hardLimit)
        try expect(!first.isEmpty, "live sample returned no processes")
        try expect(first.contains { !$0.command.isEmpty }, "no process had a readable command")

        let second = monitor.sampleSync(limit: ProcessMonitor.hardLimit)
        try expect(!second.isEmpty, "second live sample returned no processes")

        var firstByPid: [Int32: ProcessMonitor.Entry] = [:]
        for entry in first { firstByPid[entry.pid] = entry }
        for entry in second {
            if let prior = firstByPid[entry.pid], prior.identity == entry.identity {
                try expectEqual(entry.command, prior.command)
            }
        }
    }

    static func testLiveSampleMeasuresBusyProcessCPU() throws {
        // 回歸測試：pti_total_* 是 mach 單位不是 ns，忘記換算的話 Apple
        // Silicon 上 CPU% 會少 ~41.7 倍、全部顯示 0。這裡滿載一顆核心
        // 0.6 秒，自己的 process 在全機尺度下應該至少 100/cores %
        // （64 核也有 1.56%），用 1% 當保守門檻。
        let monitor = ProcessMonitor()
        _ = monitor.sampleSync(limit: ProcessMonitor.hardLimit)   // baseline

        let end = Date().addingTimeInterval(0.6)
        var sink = 0.0
        while Date() < end { sink += 1 }
        _ = sink

        let entries = monitor.sampleSync(limit: ProcessMonitor.hardLimit)
        let ownPid = ProcessInfo.processInfo.processIdentifier
        let own = entries.first { $0.pid == ownPid }
        try expect(own != nil, "own busy process missing from sample")
        try expect((own?.cpuPercent ?? 0) > 1.0,
                   "busy process shows \(own?.cpuPercent ?? 0)% CPU — unit conversion regression?")
    }

    static func testDisplayNameUsesBinaryBaseName() throws {
        try expectEqual(
            ProcessMonitor.displayName(from: "/Applications/Safari.app/Contents/MacOS/Safari"),
            "Safari"
        )
    }

    static func testDisplayNameKeepsKernelStyleNames() throws {
        try expectEqual(ProcessMonitor.displayName(from: "(kernel_task)"), "(kernel_task)")
    }

    static func testDisplayNameAddsScriptForInterpreters() throws {
        try expectEqual(
            ProcessMonitor.displayName(from: "/usr/bin/python3 /tmp/jobs/render.py --quality high"),
            "python3 render.py"
        )
        try expectEqual(
            ProcessMonitor.displayName(from: "/opt/homebrew/bin/node --inspect /Users/daniel/server.js"),
            "node server.js"
        )
    }

    static func testDisplayNameHandlesEmptyCommand() throws {
        try expectEqual(ProcessMonitor.displayName(from: ""), "—")
    }

    static func testComputeEntriesNormalizesAndSorts() throws {
        // 1 秒 wall clock，4 個 logical cores → 100% on one core == 1e9 ns / 4e9 ns 視窗 = 25%
        // 設 PID 101 用了 2e9 ns（兩個 core 滿載 1s）→ 50%
        // 設 PID 102 用了 5e8 ns（半個 core 1s）→ 12.5%
        let identityA = ProcessMonitor.ProcessIdentity(startTimeSeconds: 1, startTimeMicroseconds: 0, uid: 501)
        let identityB = ProcessMonitor.ProcessIdentity(startTimeSeconds: 2, startTimeMicroseconds: 0, uid: 501)

        let prev: [Int32: ProcessMonitor.PreviousSnapshot] = [
            101: .init(cumulativeCpuNs: 10_000_000_000, identity: identityA),
            102: .init(cumulativeCpuNs:  5_000_000_000, identity: identityB)
        ]
        let now: [ProcessMonitor.RawSample] = [
            .init(pid: 101, cumulativeCpuNs: 12_000_000_000, identity: identityA,
                  command: "/usr/bin/python3 /tmp/render.py"),
            .init(pid: 102, cumulativeCpuNs:  5_500_000_000, identity: identityB,
                  command: "/Applications/Safari.app/Contents/MacOS/Safari")
        ]

        let entries = ProcessMonitor.computeEntries(
            currentSamples: now,
            previousSnapshots: prev,
            elapsedNs: 1_000_000_000,
            activeProcessorCount: 4,
            limit: 10
        )

        try expectEqual(entries.count, 2)
        try expectEqual(entries[0].pid, 101)
        try expectEqual(entries[0].name, "python3 render.py")
        try expectClose(entries[0].cpuPercent, 50.0)
        try expectEqual(entries[1].pid, 102)
        try expectEqual(entries[1].name, "Safari")
        try expectClose(entries[1].cpuPercent, 12.5)
    }

    static func testComputeEntriesClampsCPUAtOneHundred() throws {
        // 不太可能但設一筆 delta 大於整段 wall*cores 預算（4e9 ns）的 raw 值，
        // 確保 clamp 防呆生效。
        let id = ProcessMonitor.ProcessIdentity(startTimeSeconds: 1, startTimeMicroseconds: 0, uid: 501)
        let prev: [Int32: ProcessMonitor.PreviousSnapshot] = [
            7: .init(cumulativeCpuNs: 0, identity: id)
        ]
        let now: [ProcessMonitor.RawSample] = [
            .init(pid: 7, cumulativeCpuNs: 99_000_000_000, identity: id, command: "/usr/bin/yes")
        ]

        let entries = ProcessMonitor.computeEntries(
            currentSamples: now,
            previousSnapshots: prev,
            elapsedNs: 1_000_000_000,
            activeProcessorCount: 4,
            limit: 5
        )

        try expectEqual(entries.count, 1)
        try expectClose(entries[0].cpuPercent, 100.0)
    }

    static func testComputeEntriesZeroOnFirstTick() throws {
        // 沒前一筆 snapshot — 應該回 cpu 0（不能用未知的 baseline 算 delta）。
        let id = ProcessMonitor.ProcessIdentity(startTimeSeconds: 1, startTimeMicroseconds: 0, uid: 501)
        let now: [ProcessMonitor.RawSample] = [
            .init(pid: 7, cumulativeCpuNs: 1_000_000_000, identity: id, command: "/usr/bin/yes")
        ]

        let entries = ProcessMonitor.computeEntries(
            currentSamples: now,
            previousSnapshots: [:],
            elapsedNs: 1_000_000_000,
            activeProcessorCount: 4,
            limit: 5
        )

        try expectEqual(entries.count, 1)
        try expectClose(entries[0].cpuPercent, 0.0)
    }

    static func testComputeEntriesPIDReuseGivesZero() throws {
        // 同 PID 但 identity 不同 — 視為新 process，不沿用上次的 cumulative。
        let oldId = ProcessMonitor.ProcessIdentity(startTimeSeconds: 1, startTimeMicroseconds: 0, uid: 501)
        let newId = ProcessMonitor.ProcessIdentity(startTimeSeconds: 9, startTimeMicroseconds: 0, uid: 501)
        let prev: [Int32: ProcessMonitor.PreviousSnapshot] = [
            7: .init(cumulativeCpuNs: 10_000_000_000, identity: oldId)
        ]
        let now: [ProcessMonitor.RawSample] = [
            .init(pid: 7, cumulativeCpuNs: 500_000_000, identity: newId, command: "/usr/bin/yes")
        ]

        let entries = ProcessMonitor.computeEntries(
            currentSamples: now,
            previousSnapshots: prev,
            elapsedNs: 1_000_000_000,
            activeProcessorCount: 4,
            limit: 5
        )

        try expectEqual(entries.count, 1)
        try expectClose(entries[0].cpuPercent, 0.0)
    }

    static func testComputeEntriesAppliesLimit() throws {
        let id = ProcessMonitor.ProcessIdentity(startTimeSeconds: 1, startTimeMicroseconds: 0, uid: 501)
        let prev: [Int32: ProcessMonitor.PreviousSnapshot] = [
            1: .init(cumulativeCpuNs: 0, identity: id),
            2: .init(cumulativeCpuNs: 0, identity: id),
            3: .init(cumulativeCpuNs: 0, identity: id)
        ]
        let now: [ProcessMonitor.RawSample] = [
            .init(pid: 1, cumulativeCpuNs: 100_000_000, identity: id, command: "/bin/a"),
            .init(pid: 2, cumulativeCpuNs: 300_000_000, identity: id, command: "/bin/b"),
            .init(pid: 3, cumulativeCpuNs: 200_000_000, identity: id, command: "/bin/c")
        ]

        let entries = ProcessMonitor.computeEntries(
            currentSamples: now,
            previousSnapshots: prev,
            elapsedNs: 1_000_000_000,
            activeProcessorCount: 4,
            limit: 2
        )

        try expectEqual(entries.count, 2)
        try expectEqual(entries[0].pid, 2)  // 最高 cpu
        try expectEqual(entries[1].pid, 3)
    }
}
