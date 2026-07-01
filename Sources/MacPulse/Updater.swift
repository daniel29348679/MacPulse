import Foundation
import AppKit
import CryptoKit

/// 透過 GitHub Releases API 檢查新版本，並可下載 zip → 解壓 → 替換現有 .app。
///
/// 替換的時候會寫一個 detached shell helper 到 /tmp，
/// 它會：
///   1. 等目前的 App process 結束
///   2. 把舊的 .app 移到 backup
///   3. 把新的 .app 放到原路徑並驗證可執行檔
///   4. `open` 新的 .app，失敗時嘗試 rollback
/// 然後我們就 NSApp.terminate，App 一退出 helper 接手。
enum Updater {

    static let repoOwner = "daniel29348679"
    static let repoName  = "MacPulse"

    struct Release {
        let version: String      // 去掉 leading "v"
        let zipURL: URL
        let zipAssetName: String
        let checksumURL: URL?
        let pageURL: URL
    }

    enum UpdateError: LocalizedError {
        case badResponse
        case httpStatus(Int)
        case noZipAsset
        case checksumInvalid(String)
        case checksumMismatch(expected: String, actual: String)
        case extractFailed(String)
        case appNotInExtract
        case invalidAppBundle(String)
        case notInstallable
        case scriptFailed(String)

        var errorDescription: String? {
            switch self {
            case .badResponse:        return "Could not parse GitHub response."
            case .httpStatus(let code): return "GitHub returned HTTP \(code)."
            case .noZipAsset:         return "Latest release has no .zip asset."
            case .checksumInvalid(let m): return "Checksum could not be verified: \(m)"
            case .checksumMismatch(let expected, let actual):
                return "Checksum mismatch. Expected \(expected), got \(actual)."
            case .extractFailed(let m): return "Extraction failed: \(m)"
            case .appNotInExtract:    return "Could not find MacPulse.app in the downloaded archive."
            case .invalidAppBundle(let m): return "Downloaded app bundle is invalid: \(m)"
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
        let r = normalizedVersion(remote).split(separator: ".").map { Int($0.prefix { $0.isNumber }) ?? 0 }
        let l = normalizedVersion(local).split(separator: ".").map  { Int($0.prefix { $0.isNumber }) ?? 0 }
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

        URLSession.shared.dataTask(with: req) { data, response, error in
            if let error {
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }
            // GitHub 回 4xx/5xx（rate limit 之類）時 body 是 error JSON，
            // 不先擋下來會 decode 失敗、回報成看不懂的解析錯誤。
            if let http = response as? HTTPURLResponse,
               !(200..<300).contains(http.statusCode) {
                DispatchQueue.main.async { completion(.failure(UpdateError.httpStatus(http.statusCode))) }
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
                    struct Asset: Decodable, AssetLike {
                        let name: String
                        let browser_download_url: String
                    }
                }
                let payload = try JSONDecoder().decode(Payload.self, from: data)
                let version = normalizedVersion(payload.tag_name)
                let expectedZipName = expectedZipAssetName(tagName: payload.tag_name, version: version)
                // 這些 URL 是遠端回應裡的字串，之後會餵給 URLSession 與
                // NSWorkspace.open — 一律只接受 https，擋掉其他 scheme。
                guard let asset = selectedZipAsset(from: payload.assets,
                                                   expectedZipName: expectedZipName,
                                                   version: version),
                      let zipURL = httpsURL(asset.browser_download_url),
                      let pageURL = httpsURL(payload.html_url) else {
                    DispatchQueue.main.async { completion(.failure(UpdateError.noZipAsset)) }
                    return
                }
                let checksumAsset = payload.assets.first { $0.name == "\(asset.name).sha256" }
                    ?? payload.assets.first { $0.name == "\(expectedZipName).sha256" }
                let checksumURL: URL?
                if let checksumAsset {
                    guard let url = httpsURL(checksumAsset.browser_download_url) else {
                        DispatchQueue.main.async { completion(.failure(UpdateError.badResponse)) }
                        return
                    }
                    checksumURL = url
                } else {
                    checksumURL = nil
                }
                DispatchQueue.main.async {
                    completion(.success(Release(version: version,
                                                zipURL: zipURL,
                                                zipAssetName: asset.name,
                                                checksumURL: checksumURL,
                                                pageURL: pageURL)))
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

        let task = URLSession.shared.downloadTask(with: release.zipURL) { tempURL, response, error in
            if let error {
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }
            // 404 之類的 error page 也會「下載成功」，先擋掉，
            // 不然要等到 checksum 驗證才 fail、訊息也難懂。
            if let http = response as? HTTPURLResponse,
               !(200..<300).contains(http.statusCode) {
                DispatchQueue.main.async { completion(.failure(UpdateError.httpStatus(http.statusCode))) }
                return
            }
            guard let tempURL else {
                DispatchQueue.main.async { completion(.failure(UpdateError.badResponse)) }
                return
            }
            do {
                let staged = try stageDownloadedZip(at: tempURL, release: release)
                verifyAndInstall(zipPath: staged.zipPath,
                                 workDir: staged.workDir,
                                 release: release,
                                 completion: completion)
            } catch {
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
        task.resume()
    }

    private static func stageDownloadedZip(at tempURL: URL,
                                           release: Release) throws -> (workDir: URL, zipPath: URL) {
        let fm = FileManager.default

        // Asset 名稱來自遠端 API 回應 — 只能當單一檔名用。含路徑分隔符
        // 或 "." / ".." 的名稱可能讓 zip 被寫到 workDir 之外，直接拒絕。
        let assetName = release.zipAssetName
        guard !assetName.isEmpty, !assetName.contains("/"),
              assetName != ".", assetName != ".." else {
            throw UpdateError.badResponse
        }

        // 把下載到的暫存檔挪到一個有 .zip 副檔名的位置，方便 ditto 處理
        let workDir = fm.temporaryDirectory.appendingPathComponent("macpulse-update-\(UUID().uuidString)")
        try fm.createDirectory(at: workDir, withIntermediateDirectories: true)

        let zipPath = workDir.appendingPathComponent(assetName)
        if fm.fileExists(atPath: zipPath.path) { try? fm.removeItem(at: zipPath) }
        try fm.moveItem(at: tempURL, to: zipPath)
        return (workDir, zipPath)
    }

    private static func verifyAndInstall(zipPath: URL,
                                         workDir: URL,
                                         release: Release,
                                         completion: @escaping (Result<Void, Error>) -> Void) {
        let finish: (Result<Void, Error>) -> Void = { result in
            if case .failure = result {
                try? FileManager.default.removeItem(at: workDir)
            }
            DispatchQueue.main.async { completion(result) }
        }

        let install: () -> Void = {
            do {
                try installFromZip(at: zipPath, workDir: workDir, release: release)
                // installFromZip 啟動 helper 後會自己 terminate，
                // 不會走到這行；但保險起見 callback 一個 success
                finish(.success(()))
            } catch {
                finish(.failure(error))
            }
        }

        guard let checksumURL = release.checksumURL else {
            finish(.failure(UpdateError.checksumInvalid("Latest release has no matching .sha256 asset.")))
            return
        }

        fetchExpectedChecksum(from: checksumURL) { result in
            do {
                let expected = try result.get()
                try verifyChecksum(of: zipPath, expected: expected)
                install()
            } catch {
                finish(.failure(error))
            }
        }
    }

    private static func installFromZip(at zipPath: URL, workDir: URL, release: Release) throws {
        let fm = FileManager.default

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
        try validateExtractedApp(newApp, release: release)

        let dest = Bundle.main.bundleURL          // 目前 .app 的位置
        let pid  = ProcessInfo.processInfo.processIdentifier
        let backup = dest.deletingLastPathComponent()
            .appendingPathComponent("\(dest.lastPathComponent).backup-\(UUID().uuidString)")

        // 寫一個 helper 腳本：等本 process 死掉、替換 .app、重新打開
        let scriptPath = workDir.appendingPathComponent("install.sh")
        let script = """
        #!/bin/bash
        # MacPulse self-updater helper
        set -u
        DEST=\(shellQuote(dest.path))
        NEW_APP=\(shellQuote(newApp.path))
        BACKUP=\(shellQuote(backup.path))
        WORK_DIR=\(shellQuote(workDir.path))
        EXEC="$DEST/Contents/MacOS/MacPulse"
        BACKED_UP=0

        rollback() {
            if [ -d "$DEST" ]; then
                /bin/rm -rf "$DEST"
            fi
            if [ "$BACKED_UP" = "1" ] && [ -d "$BACKUP" ]; then
                /bin/mv "$BACKUP" "$DEST"
            fi
        }

        cleanup_failed_update() {
            /bin/rm -rf "$WORK_DIR"
        }

        for i in $(seq 1 600); do
            if ! /bin/kill -0 \(pid) 2>/dev/null; then break; fi
            /bin/sleep 0.1
        done
        if /bin/kill -0 \(pid) 2>/dev/null; then
            cleanup_failed_update
            exit 1
        fi
        /bin/sleep 0.3
        if [ -e "$DEST" ]; then
            if ! /bin/mv "$DEST" "$BACKUP"; then
                cleanup_failed_update
                exit 1
            fi
            BACKED_UP=1
        fi
        if ! /bin/mv "$NEW_APP" "$DEST"; then
            rollback
            cleanup_failed_update
            exit 1
        fi
        if [ ! -x "$EXEC" ]; then
            rollback
            cleanup_failed_update
            exit 1
        fi
        /bin/sleep 0.3
        if ! /usr/bin/open "$DEST"; then
            rollback
            cleanup_failed_update
            exit 1
        fi
        if [ "$BACKED_UP" = "1" ]; then
            /bin/rm -rf "$BACKUP"
        fi
        /bin/rm -rf "$WORK_DIR"
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

    private static func validateExtractedApp(_ app: URL, release: Release) throws {
        let infoURL = app.appendingPathComponent("Contents/Info.plist")
        let data = try Data(contentsOf: infoURL)
        guard let info = try PropertyListSerialization.propertyList(from: data,
                                                                    options: [],
                                                                    format: nil) as? [String: Any] else {
            throw UpdateError.invalidAppBundle("Info.plist is not readable.")
        }

        let bundleID = info["CFBundleIdentifier"] as? String
        guard bundleID == "app.macpulse.MacPulse" else {
            throw UpdateError.invalidAppBundle("Expected bundle identifier app.macpulse.MacPulse, found \(bundleID ?? "missing").")
        }

        let bundleVersion = (info["CFBundleShortVersionString"] as? String)
            ?? (info["CFBundleVersion"] as? String)
        guard let bundleVersion,
              normalizedVersion(bundleVersion) == release.version else {
            throw UpdateError.invalidAppBundle("Expected version \(release.version), found \(bundleVersion ?? "missing").")
        }

        let executable = app.appendingPathComponent("Contents/MacOS/MacPulse")
        guard FileManager.default.isExecutableFile(atPath: executable.path) else {
            throw UpdateError.invalidAppBundle("MacPulse executable is missing or not executable.")
        }
    }

    private static func fetchExpectedChecksum(from url: URL,
                                              completion: @escaping (Result<String, Error>) -> Void) {
        var req = URLRequest(url: url)
        req.timeoutInterval = 15
        URLSession.shared.dataTask(with: req) { data, response, error in
            if let error {
                completion(.failure(error))
                return
            }
            if let http = response as? HTTPURLResponse,
               !(200..<300).contains(http.statusCode) {
                completion(.failure(UpdateError.checksumInvalid("checksum asset returned HTTP \(http.statusCode).")))
                return
            }
            guard let data,
                  let text = String(data: data, encoding: .utf8),
                  let checksum = firstSHA256Hex(in: text) else {
                completion(.failure(UpdateError.checksumInvalid("checksum asset did not contain a SHA-256 hash.")))
                return
            }
            completion(.success(checksum))
        }.resume()
    }

    private static func verifyChecksum(of fileURL: URL, expected: String) throws {
        let actual = try sha256Hex(of: fileURL)
        guard actual.caseInsensitiveCompare(expected) == .orderedSame else {
            throw UpdateError.checksumMismatch(expected: expected.lowercased(), actual: actual)
        }
    }

    private static func sha256Hex(of fileURL: URL) throws -> String {
        // 串流讀檔 — 不要把整個 zip 一次載進記憶體。
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        let digest = hasher.finalize()
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// 只接受 https 的 URL 解析 — 更新流程中所有遠端提供的連結都走這裡。
    private static func httpsURL(_ string: String) -> URL? {
        guard let url = URL(string: string),
              url.scheme?.lowercased() == "https" else { return nil }
        return url
    }

    private static func firstSHA256Hex(in text: String) -> String? {
        let trimSet = CharacterSet(charactersIn: " \t\r\n*()=")
        let hexSet = CharacterSet(charactersIn: "0123456789abcdefABCDEF")
        for rawToken in text.components(separatedBy: .whitespacesAndNewlines) {
            let token = rawToken.trimmingCharacters(in: trimSet)
            if token.count == 64,
               token.unicodeScalars.allSatisfy({ hexSet.contains($0) }) {
                return token.lowercased()
            }
        }
        return nil
    }

    private static func selectedZipAsset<T>(from assets: [T],
                                            expectedZipName: String,
                                            version: String) -> T? where T: AssetLike {
        assets.first { $0.name == expectedZipName }
            ?? assets.first { $0.name == "MacPulse-\(version).zip" }
    }

    private static func expectedZipAssetName(tagName: String, version: String) -> String {
        let releaseTag = tagName.hasPrefix("v") || tagName.hasPrefix("V") ? tagName : "v\(version)"
        return "MacPulse-\(releaseTag).zip"
    }

    private static func normalizedVersion(_ version: String) -> String {
        if version.hasPrefix("v") || version.hasPrefix("V") {
            return String(version.dropFirst())
        }
        return version
    }

    private static func shellQuote(_ s: String) -> String {
        // single-quote 包起來；內含 single-quote 改成 '\''
        let escaped = s.replacingOccurrences(of: "'", with: "'\\''")
        return "'\(escaped)'"
    }
}

private protocol AssetLike {
    var name: String { get }
}
