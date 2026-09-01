import Foundation

/// Stable identity used by process-detail routes. Live usage values change on
/// every sample, so the full `Entry` must never be used as a navigation key.
struct ProcessEntryID: Hashable {
    let pid: Int32
    let identity: ProcessMonitor.ProcessIdentity

    init(_ entry: ProcessMonitor.Entry) {
        pid = entry.pid
        identity = entry.identity
    }

    func resolve(in entries: [ProcessMonitor.Entry]) -> ProcessMonitor.Entry? {
        entries.first { $0.pid == pid && $0.identity == identity }
    }
}

enum ProcessSortMetric: Hashable, CaseIterable {
    case name
    case cpu
    case memory
    case disk

    var label: String {
        switch self {
        case .name: return "Name"
        case .cpu: return "CPU"
        case .memory: return "RAM"
        case .disk: return "I/O"
        }
    }

    func sorted(_ entries: [ProcessMonitor.Entry], ascending: Bool) -> [ProcessMonitor.Entry] {
        entries.sorted { lhs, rhs in
            let orderedBefore: Bool
            let tied: Bool
            switch self {
            case .name:
                let comparison = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
                orderedBefore = comparison == .orderedAscending
                tied = comparison == .orderedSame
            case .cpu:
                orderedBefore = lhs.cpuPercent < rhs.cpuPercent
                tied = lhs.cpuPercent == rhs.cpuPercent
            case .memory:
                orderedBefore = lhs.memoryBytes < rhs.memoryBytes
                tied = lhs.memoryBytes == rhs.memoryBytes
            case .disk:
                orderedBefore = lhs.diskBytesPerSecond < rhs.diskBytesPerSecond
                tied = lhs.diskBytesPerSecond == rhs.diskBytesPerSecond
            }
            if tied { return lhs.pid < rhs.pid }
            return ascending ? orderedBefore : !orderedBefore
        }
    }
}

/// Small, UI-independent navigation state for the process browser.
struct ProcessNavigationState {
    enum Route: Hashable {
        case processes
        case entry(id: ProcessEntryID, metric: ProcessSortMetric)
    }

    private(set) var path: [Route] = []

    var current: Route? { path.last }
    var isAtOverview: Bool { path.isEmpty }

    @discardableResult
    mutating func push(_ route: Route) -> Bool {
        guard route != path.last else { return false }
        path.append(route)
        return true
    }

    @discardableResult
    mutating func goBack() -> Route? {
        _ = path.popLast()
        return path.last
    }

    mutating func reset() {
        path.removeAll(keepingCapacity: true)
    }
}
