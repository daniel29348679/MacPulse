import Darwin
import Foundation

/// 透過 libproc + sysctl 取得依 CPU 使用率排序的行程清單。
/// 不再 fork `/bin/ps` — 在 menu bar app 上每秒 fork+exec 是最大的耗電來源之一。
///
/// CPU% 算法：
///   delta_cpu_ns / (elapsed_wall_ns * core_count) * 100
/// 換算後與整體 CPU 使用率同尺度（0–100%，多執行緒 app 仍可能持平 ≈100%）。
final class ProcessMonitor {
    struct ProcessIdentity: Hashable {
        let startTimeSeconds: Int64
        let startTimeMicroseconds: Int32
        let uid: uid_t
    }

    struct Entry: Hashable {
        let pid: Int32
        let name: String
        let command: String
        let cpuPercent: Double
        let identity: ProcessIdentity
    }

    /// 一次最多回傳幾筆 — 設定上限避免 UI 列太多。
    static let hardLimit = 50

    /// `computeEntries` 的輸入；也是 `gatherRawSamples` 的輸出。
    struct RawSample: Equatable {
        let pid: Int32
        let cumulativeCpuNs: UInt64
        let identity: ProcessIdentity
        let command: String
    }

    /// 上一筆樣本，用來算 cumulative CPU 時間的 delta。
    struct PreviousSnapshot: Equatable {
        let cumulativeCpuNs: UInt64
        let identity: ProcessIdentity
    }

    private let queue = DispatchQueue(label: "macpulse.process-monitor", qos: .userInitiated)
    private var inFlight = false

    private struct CachedCommand {
        let identity: ProcessIdentity
        let command: String
    }

    /// 以下欄位只在 `queue` 的 serial context 中讀寫。
    private var previousSnapshots: [Int32: PreviousSnapshot] = [:]
    /// 命令列快取 — argv 在 process 存活期間不變（exec 換影像的極短窗口除外，
    /// 那只影響顯示名稱），identity 對得上就不用每個 tick 重跑 KERN_PROCARGS2。
    private var commandCache: [Int32: CachedCommand] = [:]
    private var previousMach: UInt64 = 0

    /// mach absolute time → ns 的換算比。Intel 上是 1/1，Apple Silicon 上
    /// 是 125/3（24 MHz tick）。elapsed 與 pti counter 的換算都用這個。
    private static let machTimebase: mach_timebase_info_data_t = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return info
    }()

    /// 非同步取樣。若上一筆還沒回來會直接略過這次呼叫（避免堆積）。
    func sample(limit: Int, completion: @escaping ([Entry]) -> Void) {
        let cappedLimit = max(1, min(limit, Self.hardLimit))
        if inFlight { return }
        inFlight = true
        queue.async { [weak self] in
            let entries = self?.run(limit: cappedLimit) ?? []
            DispatchQueue.main.async {
                self?.inFlight = false
                completion(entries)
            }
        }
    }

    /// 同步版本 — 給單元測試或極少數需要立即取得的場合用。
    func sampleSync(limit: Int) -> [Entry] {
        return queue.sync { self.run(limit: max(1, min(limit, Self.hardLimit))) }
    }

    private func run(limit: Int) -> [Entry] {
        let nowMach = mach_absolute_time()
        let elapsedNs: Double = {
            guard previousMach > 0, nowMach > previousMach else { return 0 }
            let diff = nowMach - previousMach
            return Double(diff) * Double(Self.machTimebase.numer) / Double(Self.machTimebase.denom)
        }()

        let raw = gatherRawSamples()
        let entries = Self.computeEntries(
            currentSamples: raw,
            previousSnapshots: previousSnapshots,
            elapsedNs: elapsedNs,
            activeProcessorCount: ProcessInfo.processInfo.activeProcessorCount,
            limit: limit
        )

        // 用本次的 raw 取代 previous — 下次 tick 才有 delta 可算。
        var newPrev: [Int32: PreviousSnapshot] = [:]
        newPrev.reserveCapacity(raw.count)
        for s in raw {
            newPrev[s.pid] = PreviousSnapshot(cumulativeCpuNs: s.cumulativeCpuNs,
                                              identity: s.identity)
        }
        previousSnapshots = newPrev
        previousMach = nowMach
        return entries
    }

    // MARK: - Pure compute (testable)

    /// 把 raw 樣本 + 上一筆 snapshot 算出依 CPU% 遞減排序、套上 limit 的 Entry 清單。
    /// PID reuse（identity 對不上）或沒有前一筆樣本時，該 process 的 cpu% 視為 0。
    static func computeEntries(currentSamples: [RawSample],
                               previousSnapshots: [Int32: PreviousSnapshot],
                               elapsedNs: Double,
                               activeProcessorCount: Int,
                               limit: Int) -> [Entry] {
        let cores = Double(max(1, activeProcessorCount))
        let denom = elapsedNs > 0 ? elapsedNs * cores : 0

        var entries: [Entry] = []
        entries.reserveCapacity(currentSamples.count)
        for s in currentSamples {
            let pct: Double
            if denom > 0,
               let prev = previousSnapshots[s.pid],
               prev.identity == s.identity,
               s.cumulativeCpuNs >= prev.cumulativeCpuNs {
                let delta = Double(s.cumulativeCpuNs - prev.cumulativeCpuNs)
                pct = min(100.0, delta / denom * 100.0)
            } else {
                pct = 0
            }
            let name = displayName(from: s.command)
            entries.append(Entry(pid: s.pid,
                                 name: name,
                                 command: s.command,
                                 cpuPercent: pct,
                                 identity: s.identity))
        }
        entries.sort { $0.cpuPercent > $1.cpuPercent }
        if entries.count > limit { entries.removeLast(entries.count - limit) }
        return entries
    }

    // MARK: - libproc sampling

    /// KERN_ARGMAX 只查一次 — argv buffer 的上限（通常 256 KB–1 MB）。
    private static let argMaxBytes: Int = {
        var mib: [Int32] = [CTL_KERN, KERN_ARGMAX]
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        let ret = mib.withUnsafeMutableBufferPointer { mibPtr in
            sysctl(mibPtr.baseAddress, u_int(mibPtr.count), &value, &size, nil, 0)
        }
        return (ret == 0 && value > 0) ? Int(value) : 262_144
    }()

    private func gatherRawSamples() -> [RawSample] {
        // proc_listpids(type=0 means 'give me the buffer size'): 先問需要多大。
        let probeBytes = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
        guard probeBytes > 0 else { return [] }
        // 加一點空間 — 兩次呼叫之間有可能多生出新 process。
        let capacity = Int(probeBytes) / MemoryLayout<pid_t>.stride + 32
        var pids = [pid_t](repeating: 0, count: capacity)
        let writtenBytes = pids.withUnsafeMutableBufferPointer { ptr -> Int32 in
            proc_listpids(UInt32(PROC_ALL_PIDS),
                          0,
                          ptr.baseAddress,
                          Int32(ptr.count * MemoryLayout<pid_t>.stride))
        }
        guard writtenBytes > 0 else { return [] }
        let count = Int(writtenBytes) / MemoryLayout<pid_t>.stride

        // 一整批 process 共用同一塊 argv buffer — 不要每個 pid 各 malloc
        // 一次 argMax（256 KB+），那會是每秒上百 MB 的暫時配置。
        let argvBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: Self.argMaxBytes)
        defer { argvBuffer.deallocate() }

        var samples: [RawSample] = []
        var newCache: [Int32: CachedCommand] = [:]
        samples.reserveCapacity(count)
        newCache.reserveCapacity(count)
        for i in 0..<count {
            let pid = pids[i]
            guard pid > 0 else { continue }
            guard let cumulativeNs = Self.taskCumulativeCpuNs(pid: pid) else { continue }
            guard let identity = Self.processIdentity(for: pid) else { continue }
            let command: String
            if let cached = commandCache[pid], cached.identity == identity {
                command = cached.command
            } else {
                command = Self.readCommand(pid: pid,
                                           argvBuffer: argvBuffer,
                                           argvBufferSize: Self.argMaxBytes)
            }
            newCache[pid] = CachedCommand(identity: identity, command: command)
            samples.append(RawSample(pid: pid,
                                     cumulativeCpuNs: cumulativeNs,
                                     identity: identity,
                                     command: command))
        }
        commandCache = newCache   // 只留這次還活著的 pid，順便修剪掉舊項目
        return samples
    }

    private static func taskCumulativeCpuNs(pid: Int32) -> UInt64? {
        var info = proc_taskinfo()
        let size = MemoryLayout<proc_taskinfo>.size
        let ret = withUnsafeMutablePointer(to: &info) { ptr -> Int32 in
            proc_pidinfo(pid, PROC_PIDTASKINFO, 0, ptr, Int32(size))
        }
        guard ret == Int32(size) else { return nil }
        // pti_total_user / pti_total_system 是 mach absolute time 單位，
        // 「不是」ns — Intel 的 timebase 恰為 1/1 所以兩者數值相同（這也是
        // 常見誤解的來源），Apple Silicon 是 24 MHz tick（timebase 125/3），
        // 直接當 ns 用會把 CPU% 少算 ~41.7 倍、全部顯示成 0。
        let machUnits = info.pti_total_user &+ info.pti_total_system
        return machUnits &* UInt64(machTimebase.numer) / UInt64(machTimebase.denom)
    }

    private static func processIdentity(for pid: Int32) -> ProcessIdentity? {
        var mib = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        let mibCount = u_int(mib.count)

        let result = mib.withUnsafeMutableBufferPointer { mibPtr in
            sysctl(mibPtr.baseAddress, mibCount, &info, &size, nil, 0)
        }

        guard result == 0,
              size >= MemoryLayout<kinfo_proc>.stride,
              info.kp_proc.p_pid == pid
        else { return nil }

        let start = info.kp_proc.p_starttime
        return ProcessIdentity(startTimeSeconds: Int64(start.tv_sec),
                               startTimeMicroseconds: Int32(start.tv_usec),
                               uid: info.kp_eproc.e_ucred.cr_uid)
    }

    /// 拿 process 的完整命令列（argv 串接）。失敗時 fallback 到 proc_pidpath，
    /// 再不行就用 `(name)` 比照 `ps` 對 kernel-only thread 的呈現。
    /// `argvBuffer` 由呼叫端提供並在多個 pid 間重複使用（至少 argMaxBytes 大）。
    private static func readCommand(pid: Int32,
                                    argvBuffer: UnsafeMutablePointer<UInt8>,
                                    argvBufferSize: Int) -> String {
        if let args = processArgv(pid: pid, buffer: argvBuffer, bufferSize: argvBufferSize),
           !args.isEmpty {
            return args.joined(separator: " ")
        }
        // PROC_PIDPATHINFO_MAXSIZE = 4 * MAXPATHLEN = 4096；
        // 該 macro 在 Swift importer 看不到（structure not supported）。
        let pathBufSize = 4096
        var path = [CChar](repeating: 0, count: pathBufSize)
        let n = proc_pidpath(pid, &path, UInt32(pathBufSize))
        if n > 0 { return String(cString: path) }

        var nameBuf = [CChar](repeating: 0, count: 256)
        let nameLen = proc_name(pid, &nameBuf, UInt32(nameBuf.count))
        if nameLen > 0 {
            let n = String(cString: nameBuf)
            return n.isEmpty ? "" : "(\(n))"
        }
        return ""
    }

    /// 透過 `sysctl(KERN_PROCARGS2)` 拿 process argv。其他 user 的 process 會回 EPERM → nil。
    /// Layout: [int32 argc][exec_path\0...][nul padding][argv0\0 argv1\0 ...][envp\0 ...]
    /// `buffer` 由呼叫端提供（至少 argMaxBytes），避免每個 pid 反覆配置大塊記憶體。
    private static func processArgv(pid: Int32,
                                    buffer: UnsafeMutablePointer<UInt8>,
                                    bufferSize: Int) -> [String]? {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = bufferSize
        let ret = mib.withUnsafeMutableBufferPointer { mibPtr in
            sysctl(mibPtr.baseAddress, u_int(mibPtr.count), buffer, &size, nil, 0)
        }
        guard ret == 0, size >= MemoryLayout<Int32>.size else { return nil }

        let argc = buffer.withMemoryRebound(to: Int32.self, capacity: 1) { $0.pointee }
        guard argc > 0 else { return nil }

        var idx = MemoryLayout<Int32>.size
        // 跳過 exec path（一段 null-terminated 字串），然後是任意數量的 nul 對齊。
        while idx < size, buffer[idx] != 0 { idx += 1 }
        while idx < size, buffer[idx] == 0 { idx += 1 }

        var args: [String] = []
        args.reserveCapacity(Int(argc))
        var start = idx
        var collected: Int32 = 0
        while idx < size, collected < argc {
            if buffer[idx] == 0 {
                if idx > start {
                    let data = Data(bytes: buffer.advanced(by: start), count: idx - start)
                    if let s = String(data: data, encoding: .utf8) {
                        args.append(s)
                    }
                }
                collected += 1
                idx += 1
                start = idx
            } else {
                idx += 1
            }
        }
        return args.isEmpty ? nil : args
    }

    // MARK: - Display name

    /// 把命令列轉成一個有意義的顯示名稱。
    /// - 直接執行的 binary → 取 basename（例：`/Applications/Safari.app/.../Safari` → `Safari`）
    /// - 用 interpreter 跑的 script → 顯示「interpreter script.py」這類組合，方便辨識多個同 interpreter 的 job
    /// - kernel-only thread 慣例上會被包成 `(name)`，原樣保留。
    static func displayName(from args: String) -> String {
        if args.hasPrefix("(") && args.hasSuffix(")") {
            return args
        }
        let tokens = args.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard let exec = tokens.first else { return args.isEmpty ? "—" : args }
        let execBase = (exec as NSString).lastPathComponent
        if Self.interpreters.contains(execBase) {
            // 找第一個不以 - 開頭的 argument 當作 script。
            for token in tokens.dropFirst() {
                if token.hasPrefix("-") { continue }
                let scriptBase = (token as NSString).lastPathComponent
                if !scriptBase.isEmpty {
                    return "\(execBase) \(scriptBase)"
                }
            }
        }
        return execBase
    }

    private static let interpreters: Set<String> = [
        "python", "python2", "python3", "Python",
        "ruby", "Ruby",
        "node", "deno", "bun", "tsx",
        "perl", "php",
        "bash", "sh", "zsh", "fish", "dash",
        "java"
    ]

    // MARK: - Termination

    enum QuitResult {
        case success
        case notPermitted
        case noSuchProcess
        case staleProcess
        case failed(Int32)
    }

    /// 送 SIGTERM — 讓行程自己收尾。
    @discardableResult
    func gracefulQuit(_ entry: Entry) -> QuitResult {
        return Self.send(signal: SIGTERM, to: entry)
    }

    /// 送 SIGKILL — 強制結束。
    @discardableResult
    func forceKill(_ entry: Entry) -> QuitResult {
        return Self.send(signal: SIGKILL, to: entry)
    }

    private static func send(signal: Int32, to entry: Entry) -> QuitResult {
        guard let currentIdentity = processIdentity(for: entry.pid) else {
            return .noSuchProcess
        }
        guard currentIdentity == entry.identity else {
            return .staleProcess
        }

        let ret = kill(entry.pid, signal)
        if ret == 0 { return .success }
        switch errno {
        case EPERM: return .notPermitted
        case ESRCH: return .noSuchProcess
        default:    return .failed(errno)
        }
    }
}
