import Foundation
import AppKit

/// 透過 GitHub Releases API 檢查新版本，並可下載 zip → 解壓 → 替換現有 .app。
///
/// 替換的時候會寫一個 detached shell helper 到 /tmp，
/// 它會：
///   1. 等目前的 App process 結束
///   2. 把舊的 .app 整個換成新的
///   3. `open` 新的 .app
/// 然後我們就 NSApp.terminate，App 一退出 helper 接手。
enum Updater {

    static let repoOwner = "daniel29348679"
    static let repoName  = "MacPulse"

    struct Release {
        let version: String      // 去掉 leading "v"
        let zipURL: URL
        let pageURL: URL
    }

    enum UpdateError: LocalizedError {
        case badResponse
        case noZipAsset
        case extractFailed(String)
        case appNotInExtract
        case notInstallable
        case scriptFailed(String)

        var errorDescription: String? {
            switch self {
            case .badResponse:        return "Could not parse GitHub response."
            case .noZipAsset:         return "Latest release has no .zip asset."
            case .extractFailed(let m): return "Extraction failed: \(m)"
            case .appNotInExtract:    return "Could not find MacPulse.app in the downloaded archive."
            case .notInstallable:     return "Auto-update only works when running from MacPulse.app (not `swift run`)."
            case .scriptFailed(let m):return "Installer script failed: \(m)"
            }
        }
    }

    static func currentVersion() -> String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    /// 是否能執行替換（必須是 .app bundle 形式）
    static var isInstallable: Bool {
        Bundle.main.bundleURL.pathExtension == "app"
    }

    // MARK: - Version compare

    /// 比 "1.2.10" > "1.2.9" 之類的；非數字部分忽略。
    static func isNewer(_ remote: String, than local: String) -> Bool {
        let r = remote.split(separator: ".").map { Int($0.prefix { $0.isNumber }) ?? 0 }
        let l = local.split(separator: ".").map  { Int($0.prefix { $0.isNumber }) ?? 0 }
        for i in 0..<max(r.count, l.count) {
            let rv = i < r.count ? r[i] : 0
            let lv = i < l.count ? l[i] : 0
            if rv != lv { return rv > lv }
        }
        return false
    }

    // MARK: - Fetch latest release

    static func fetchLatestRelease(completion: @escaping (Result<Release, Error>) -> Void) {
        let url = URL(string: "https://api.github.com/repos/\(repoOwner)/\(repoName)/releases/latest")!
        var req = URLRequest(url: url)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.timeoutInterval = 15

        URLSession.shared.dataTask(with: req) { data, _, error in
            if let error {
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }
            guard let data else {
                DispatchQueue.main.async { completion(.failure(UpdateError.badResponse)) }
                return
            }
            do {
                struct Payload: Decodable {
                    let tag_name: String
                    let html_url: String
                    let assets: [Asset]
                    struct Asset: Decodable {
                        let name: String
                        let browser_download_url: String
                    }
                }
                let payload = try JSONDecoder().decode(Payload.self, from: data)
                let version = payload.tag_name.hasPrefix("v")
                    ? String(payload.tag_name.dropFirst())
                    : payload.tag_name
                guard let asset = payload.assets.first(where: { $0.name.hasSuffix(".zip") }),
                      let zipURL = URL(string: asset.browser_download_url),
                      let pageURL = URL(string: payload.html_url) else {
                    DispatchQueue.main.async { completion(.failure(UpdateError.noZipAsset)) }
                    return
                }
                DispatchQueue.main.async {
                    completion(.success(Release(version: version, zipURL: zipURL, pageURL: pageURL)))
                }
            } catch {
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }.resume()
    }

    // MARK: - Download + install

    /// 下載 release zip、解壓、然後背景執行 helper 替換並重啟。
    /// 成功時會自動 terminate 目前 App；callback 只在「啟動 helper 之前」失敗時才呼叫。
    static func downloadAndInstall(release: Release,
                                   completion: @escaping (Result<Void, Error>) -> Void) {
        guard isInstallable else {
            DispatchQueue.main.async { completion(.failure(UpdateError.notInstallable)) }
            return
        }

        let task = URLSession.shared.downloadTask(with: release.zipURL) { tempURL, _, error in
            if let error {
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }
            guard let tempURL else {
                DispatchQueue.main.async { completion(.failure(UpdateError.badResponse)) }
                return
            }
            do {
                try installFromZip(at: tempURL, release: release)
                // installFromZip 啟動 helper 後會自己 terminate，
                // 不會走到這行；但保險起見 callback 一個 success
                DispatchQueue.main.async { completion(.success(())) }
            } catch {
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
        task.resume()
    }

    private static func installFromZip(at zipURL: URL, release: Release) throws {
        let fm = FileManager.default

        // 把下載到的暫存檔挪到一個有 .zip 副檔名的位置，方便 ditto 處理
        let workDir = fm.temporaryDirectory.appendingPathComponent("macpulse-update-\(UUID().uuidString)")
        try fm.createDirectory(at: workDir, withIntermediateDirectories: true)

        let zipPath = workDir.appendingPathComponent("MacPulse-\(release.version).zip")
        if fm.fileExists(atPath: zipPath.path) { try? fm.removeItem(at: zipPath) }
        try fm.moveItem(at: zipURL, to: zipPath)

        let extractDir = workDir.appendingPathComponent("extracted")
        try fm.createDirectory(at: extractDir, withIntermediateDirectories: true)

        // ditto -xk <zip> <dest>
        let ditto = Process()
        ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        ditto.arguments = ["-xk", zipPath.path, extractDir.path]
        let errPipe = Pipe()
        ditto.standardError = errPipe
        try ditto.run()
        ditto.waitUntilExit()
        guard ditto.terminationStatus == 0 else {
            let msg = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "exit \(ditto.terminationStatus)"
            throw UpdateError.extractFailed(msg)
        }

        // 找出解壓後的 MacPulse.app
        guard let newApp = findApp(in: extractDir) else {
            throw UpdateError.appNotInExtract
        }

        let dest = Bundle.main.bundleURL          // 目前 .app 的位置
        let pid  = ProcessInfo.processInfo.processIdentifier

        // 寫一個 helper 腳本：等本 process 死掉、替換 .app、重新打開
        let scriptPath = workDir.appendingPathComponent("install.sh")
        let script = """
        #!/bin/bash
        # MacPulse self-updater helper
        for i in $(seq 1 600); do
            if ! /bin/kill -0 \(pid) 2>/dev/null; then break; fi
            /bin/sleep 0.1
        done
        /bin/sleep 0.3
        /bin/rm -rf \(shellQuote(dest.path))
        /bin/mv \(shellQuote(newApp.path)) \(shellQuote(dest.path))
        /bin/sleep 0.3
        /usr/bin/open \(shellQuote(dest.path))
        /bin/rm -rf \(shellQuote(workDir.path))
        """
        try script.data(using: .utf8)!.write(to: scriptPath)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptPath.path)

        // detach 啟動 helper
        let helper = Process()
        helper.executableURL = URL(fileURLWithPath: "/bin/bash")
        helper.arguments = [scriptPath.path]
        helper.standardOutput = nil
        helper.standardError  = nil
        helper.standardInput  = nil
        try helper.run()
        // 不 waitUntilExit — 我們要它在背景活著

        // 結束本 App，讓 helper 接手
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            NSApp.terminate(nil)
        }
    }

    private static func findApp(in directory: URL) -> URL? {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(at: directory,
                                                        includingPropertiesForKeys: nil) else {
            return nil
        }
        // 先看當層
        for url in entries where url.pathExtension == "app" {
            return url
        }
        // 再深入一層找
        for url in entries {
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                if let nested = findApp(in: url) { return nested }
            }
        }
        return nil
    }

    private static func shellQuote(_ s: String) -> String {
        // single-quote 包起來；內含 single-quote 改成 '\''
        let escaped = s.replacingOccurrences(of: "'", with: "'\\''")
        return "'\(escaped)'"
    }
}
