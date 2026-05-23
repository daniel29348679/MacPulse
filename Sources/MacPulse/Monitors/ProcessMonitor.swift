import Darwin
import Foundation

/// 透過 `ps` 取得依 CPU 使用率排序的行程清單。
/// `ps` 在背景 queue 執行，回呼回到 main queue 給 UI 用。
final class ProcessMonitor {
    struct Entry: Hashable {
        let pid: Int32
        let name: String
        let command: String
        let cpuPercent: Double
    }

    /// 一次最多抓多少筆 — 設定上限避免極端情況下 ps 輸出過大。
    static let hardLimit = 50

    private let queue = DispatchQueue(label: "macpulse.process-monitor", qos: .userInitiated)
    private var inFlight = false

    /// 非同步取樣。若上一筆還沒回來會直接略過這次呼叫（避免堆積）。
    func sample(limit: Int, completion: @escaping ([Entry]) -> Void) {
        let cappedLimit = max(1, min(limit, Self.hardLimit))
        if inFlight { return }
        inFlight = true
        queue.async { [weak self] in
            let entries = Self.run(limit: cappedLimit)
            DispatchQueue.main.async {
                self?.inFlight = false
                completion(entries)
            }
        }
    }

    /// 同步版本 — 給單元測試或極少數需要立即取得的場合用。
    func sampleSync(limit: Int) -> [Entry] {
        return Self.run(limit: max(1, min(limit, Self.hardLimit)))
    }

    private static func run(limit: Int) -> [Entry] {
        let task = Foundation.Process()
        task.launchPath = "/bin/ps"
        // -A: 所有行程；-ww: 不裁切 args；-r: 依 CPU 排序遞減；
        // args= 給完整的命令列，這樣 python/node 這類 interpreter 才能看到實際在跑什麼 script。
        task.arguments = ["-Awwo", "pid=,pcpu=,args=", "-r"]

        let outPipe = Pipe()
        let errPipe = Pipe()
        task.standardOutput = outPipe
        task.standardError = errPipe

        do {
            try task.run()
        } catch {
            return []
        }

        let data = outPipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        _ = errPipe.fileHandleForReading.readDataToEndOfFile()

        guard let output = String(data: data, encoding: .utf8) else { return [] }

        var result: [Entry] = []
        result.reserveCapacity(limit)
        for rawLine in output.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            // pid / pcpu / args — args 可能含空白，所以 maxSplits=2 把剩下整段當 args。
            let parts = line.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
            guard parts.count >= 2,
                  let pid = Int32(parts[0]),
                  let pcpu = Double(parts[1])
            else { continue }
            let command = parts.count >= 3 ? String(parts[2]) : ""
            let name = displayName(from: command)
            result.append(Entry(pid: pid, name: name, command: command, cpuPercent: pcpu))
            if result.count >= limit { break }
        }
        return result
    }

    /// 把 `ps` 的 args 欄轉成一個有意義的顯示名稱。
    /// - 直接執行的 binary → 取 basename（例：`/Applications/Safari.app/.../Safari` → `Safari`）
    /// - 用 interpreter 跑的 script → 顯示「interpreter script.py」這類組合，方便辨識多個同 interpreter 的 job
    static func displayName(from args: String) -> String {
        // ps 有時對 kernel-only thread 會印類似 "(kernel_task)"，原樣保留。
        if args.hasPrefix("(") && args.hasSuffix(")") {
            return args
        }
        let tokens = args.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard let exec = tokens.first else { return args.isEmpty ? "—" : args }
        let execBase = (exec as NSString).lastPathComponent
        let interpreters: Set<String> = [
            "python", "python2", "python3", "Python",
            "ruby", "node", "deno", "bun", "tsx",
            "perl", "php",
            "bash", "sh", "zsh", "fish", "dash",
            "java", "ruby", "Ruby"
        ]
        if interpreters.contains(execBase) {
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

    // MARK: - Termination

    enum QuitResult {
        case success
        case notPermitted
        case noSuchProcess
        case failed(Int32)
    }

    /// 送 SIGTERM — 讓行程自己收尾。
    @discardableResult
    func gracefulQuit(pid: Int32) -> QuitResult {
        return Self.send(signal: SIGTERM, to: pid)
    }

    /// 送 SIGKILL — 強制結束。
    @discardableResult
    func forceKill(pid: Int32) -> QuitResult {
        return Self.send(signal: SIGKILL, to: pid)
    }

    private static func send(signal: Int32, to pid: Int32) -> QuitResult {
        let ret = kill(pid, signal)
        if ret == 0 { return .success }
        switch errno {
        case EPERM: return .notPermitted
        case ESRCH: return .noSuchProcess
        default:    return .failed(errno)
        }
    }
}
