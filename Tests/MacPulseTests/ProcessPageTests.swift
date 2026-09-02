import AppKit
@testable import MacPulse

enum ProcessPageTests {
    static let tests: [MacPulseTestCase] = [
        MacPulseTestCase("Process page handles a thousand rows with a reusable table", testLargeProcessTable),
        MacPulseTestCase("Process navigation expands and restores the popover", testProcessPageSize)
    ]

    static func testLargeProcessTable() throws {
        let entries = (1...1_000).map { value -> ProcessMonitor.Entry in
            let pid = Int32(value)
            return .init(pid: pid,
                         name: "Process \(value)",
                         command: "/usr/bin/process-\(value)",
                         cpuPercent: Double(value % 100),
                         memoryBytes: UInt64(value) * 1_048_576,
                         diskBytesPerSecond: Double(value * 1_024),
                         identity: .init(startTimeSeconds: Int64(value),
                                         startTimeMicroseconds: 0,
                                         uid: 501))
        }

        let started = CFAbsoluteTimeGetCurrent()
        let page = ProcessTaskManagerPageView(entries: entries)
        page.frame = NSRect(x: 0, y: 0, width: 324, height: 500)
        page.layoutSubtreeIfNeeded()
        let elapsed = CFAbsoluteTimeGetCurrent() - started

        guard let table: NSTableView = firstSubview(of: NSTableView.self, in: page) else {
            throw MacPulseTestFailure(message: "process page did not contain an NSTableView",
                                      file: #filePath,
                                      line: #line)
        }
        try expectEqual(table.numberOfRows, 1_000)
        try expectEqual(table.numberOfColumns, 4)
        try expect(elapsed < 3,
                   "large process table took \(elapsed) seconds to build")

        table.sortDescriptors = [NSSortDescriptor(key: "memory", ascending: false)]
        let firstNameCell = table.view(atColumn: 0, row: 0, makeIfNecessary: true)
        try expectEqual(firstNameCell?.toolTip, "/usr/bin/process-1000")
    }

    static func testProcessPageSize() throws {
        let controller = StatsPopoverController()
        let root = controller.view

        guard let processesButton = firstSubview(of: NSButton.self,
                                                 in: root,
                                                 matching: { $0.toolTip == "View all processes" }) else {
            throw MacPulseTestFailure(message: "process navigation button was not found",
                                      file: #filePath,
                                      line: #line)
        }
        processesButton.performClick(nil)
        try expectEqual(controller.preferredContentSize.width,
                        MacPulseVisualStyle.processPopoverWidth)

        guard let processPage = firstSubview(of: ProcessPageView.self, in: root) else {
            throw MacPulseTestFailure(message: "process page was not found",
                                      file: #filePath,
                                      line: #line)
        }
        processPage.cancelOperation(nil)
        try expectEqual(controller.preferredContentSize.width,
                        MacPulseVisualStyle.popoverWidth)
    }

    private static func firstSubview<T: NSView>(of type: T.Type,
                                                in root: NSView,
                                                matching predicate: (T) -> Bool = { _ in true }) -> T? {
        if let match = root as? T, predicate(match) { return match }
        for child in root.subviews {
            if let match: T = firstSubview(of: type, in: child, matching: predicate) {
                return match
            }
        }
        return nil
    }
}
