import AppKit

// 偵錯：列出所有 HID 溫度感測器並結束
if CommandLine.arguments.contains("--dump-sensors") {
    let readings = TemperatureSensors.read()
    if readings.isEmpty {
        print("(no temperature sensors readable via IOHID)")
    } else {
        for r in readings.sorted(by: { $0.celsius > $1.celsius }) {
            let name = r.name.padding(toLength: 42, withPad: " ", startingAt: 0)
            print("\(name)\(String(format: "%6.1f °C", r.celsius))")
        }
        if let cpu = TemperatureSensors.cpuCelsius() {
            print(String(format: "\nCPU estimate: %.1f °C", cpu))
        }
    }
    exit(0)
}

// Render README screenshots and exit. Used from `scripts/make-screenshots.sh`.
if let i = CommandLine.arguments.firstIndex(of: "--render-screenshots"),
   i + 1 < CommandLine.arguments.count {
    let outDir = URL(fileURLWithPath: CommandLine.arguments[i + 1])
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    do {
        try Screenshots.render(into: outDir)
        exit(0)
    } catch {
        FileHandle.standardError.write(Data("error: \(error)\n".utf8))
        exit(1)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
// 純選單列 App，不要 dock 圖示也不要主視窗
app.setActivationPolicy(.accessory)
app.run()
