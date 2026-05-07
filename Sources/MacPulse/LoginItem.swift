import Foundation
import ServiceManagement

/// 開機自動啟動設定。底層使用 SMAppService（macOS 13+），
/// 只有當 App 是以正式 .app bundle 形式執行時才有效；
/// 從 `swift run` 直接跑的開發二進位無法註冊。
enum LoginItem {
    /// 是否能在當前執行環境註冊／反註冊。開發階段（純 CLI 二進位）會傳 false。
    static var isSupported: Bool {
        Bundle.main.bundleURL.pathExtension == "app"
    }

    static var isEnabled: Bool {
        guard isSupported else { return false }
        return SMAppService.mainApp.status == .enabled
    }

    /// 切換 login item 註冊狀態。失敗會丟錯（呼叫端負責顯示）。
    static func setEnabled(_ enabled: Bool) throws {
        guard isSupported else {
            throw NSError(
                domain: "MacPulse.LoginItem",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey:
                            "Launch at login requires running MacPulse.app from a bundle (e.g. /Applications)."]
            )
        }
        let service = SMAppService.mainApp
        if enabled {
            if service.status != .enabled {
                try service.register()
            }
        } else {
            if service.status == .enabled {
                try service.unregister()
            }
        }
    }
}
