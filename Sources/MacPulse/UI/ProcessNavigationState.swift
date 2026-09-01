import Foundation

/// Stable identity used by process-detail routes. CPU and RAM values change on
/// every sample, so the full `Entry` must never be used as a navigation key.
struct ProcessEntryID: Hashable {
    let pid: Int32
    let identity: ProcessMonitor.ProcessIdentity

    init(_ entry: ProcessMonitor.Entry) {
        pid = entry.pid
        identity = entry.identity
    }

    func resolve(in groups: [ProcessMonitor.Group], groupName: String) -> ProcessMonitor.Entry? {
        groups.first(where: { $0.name == groupName })?
            .entries.first(where: { $0.pid == pid && $0.identity == identity })
    }
}

/// Small, UI-independent navigation state for the process browser.
struct ProcessNavigationState {
    enum Route: Hashable {
        case list(ProcessMonitor.Resource)
        case group(ProcessMonitor.Resource, name: String)
        case entry(ProcessMonitor.Resource, groupName: String, id: ProcessEntryID)

        var resource: ProcessMonitor.Resource {
            switch self {
            case .list(let resource),
                 .group(let resource, _),
                 .entry(let resource, _, _):
                return resource
            }
        }
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
