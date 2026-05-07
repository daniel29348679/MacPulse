import AppKit

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
// 純選單列 App，不要 dock 圖示也不要主視窗
app.setActivationPolicy(.accessory)
app.run()
