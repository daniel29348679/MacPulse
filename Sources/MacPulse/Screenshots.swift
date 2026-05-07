import AppKit

/// Renders the popover and settings window to PNGs without touching the
/// real menu bar. Used by `MacPulse --render-screenshots <dir>` to keep
/// README marketing shots in sync with the actual UI code.
enum Screenshots {
    static func render(into directory: URL) throws {
        let fm = FileManager.default
        try? fm.createDirectory(at: directory, withIntermediateDirectories: true)

        // Snapshot + override UserDefaults so user-side preferences
        // (e.g. a 10-min sparkline window) don't distort the marketing shot.
        // Restored at the end so running this on your live install is harmless.
        let defaults = UserDefaults.standard
        let backupInterval = defaults.object(forKey: "macpulse.updateInterval")
        let backupWindow = defaults.object(forKey: "macpulse.sparkline.window")
        defaults.set(1.0, forKey: "macpulse.updateInterval")
        defaults.set(60.0, forKey: "macpulse.sparkline.window")
        defer {
            if let v = backupInterval { defaults.set(v, forKey: "macpulse.updateInterval") }
            else { defaults.removeObject(forKey: "macpulse.updateInterval") }
            if let v = backupWindow { defaults.set(v, forKey: "macpulse.sparkline.window") }
            else { defaults.removeObject(forKey: "macpulse.sparkline.window") }
        }

        // --- Popover (synthetic but realistic numbers) ---
        let popover = StatsPopoverController()
        _ = popover.view  // force loadView()
        popover.applyVisibility()
        popover.applySparklineCapacity()

        // Prime the sparklines with a believable curve so charts aren't flat.
        primeSparklines(popover)

        let cpu     = CPUMonitor.Sample(user: 9.2, system: 4.1, idle: 86.7)
        let memory  = MemoryMonitor.Sample(usedBytes:  UInt64(11.2 * 1024 * 1024 * 1024),
                                           totalBytes: UInt64(16   * 1024 * 1024 * 1024))
        let network = NetworkMonitor.Sample(downloadBytesPerSec: 1_240_000,
                                            uploadBytesPerSec:    234_000)
        let disk    = DiskMonitor.Sample(readBytesPerSec: 4 * 1024 * 1024,
                                         writeBytesPerSec: 760 * 1024)
        let temp    = TemperatureMonitor.Sample(celsius: 47, level: .nominal)
        let power   = PowerMonitor.Sample(state: .discharging, watts: 12.4, percent: 84)
        popover.update(cpu: cpu, memory: memory, network: network,
                       disk: disk, temperature: temp, power: power)

        let view = popover.view
        view.layoutSubtreeIfNeeded()
        let size = view.fittingSize

        // Host the view in a real (offscreen) window so AppKit text/measure paths work.
        let host = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                            styleMask: [.borderless],
                            backing: .buffered,
                            defer: false)
        host.contentView = view
        host.isReleasedWhenClosed = false
        host.backgroundColor = NSColor.windowBackgroundColor
        view.layoutSubtreeIfNeeded()

        try writePNG(view: view, to: directory.appendingPathComponent("popover.png"))

        // Render a charging variant too, so the README can show both states.
        let powerCharging = PowerMonitor.Sample(state: .charging, watts: 38.7, percent: 62)
        popover.update(cpu: cpu, memory: memory, network: network,
                       disk: disk, temperature: temp, power: powerCharging)
        view.layoutSubtreeIfNeeded()
        try writePNG(view: view, to: directory.appendingPathComponent("popover-charging.png"))
        host.orderOut(nil)

        // --- Settings window ---
        let settings = SettingsWindowController.shared
        settings.show()
        guard let window = settings.window, let content = window.contentView else { return }
        content.layoutSubtreeIfNeeded()
        try writePNG(view: content, to: directory.appendingPathComponent("settings.png"))
        window.orderOut(nil)
    }

    private static func primeSparklines(_ popover: StatsPopoverController) {
        let cpuCurve: [Double] = [
            8, 9, 11, 14, 18, 22, 26, 30, 33, 35, 32, 28, 24, 20, 17, 14, 12, 10,
            8, 7, 9, 12, 16, 21, 25, 28, 30, 27, 22, 17, 13, 10, 8, 7, 9, 11,
            14, 17, 20, 23, 25, 24, 22, 18, 14, 11, 9, 8, 9, 11, 13, 14, 13, 12,
            11, 10, 9, 9, 10, 11
        ]
        let memCurve: [Double] = (0..<60).map { i in 65.0 + 5.0 * sin(Double(i) / 8.0) }
        let netCurve: [Double] = (0..<60).map { i in
            let base = 600_000.0 + 400_000.0 * sin(Double(i) / 5.0)
            let burst = (i % 11 == 0) ? 1_500_000.0 : 0
            return max(0, base + burst)
        }

        // Push samples through the public update() path so the charts pick them up.
        for i in 0..<cpuCurve.count {
            popover.update(
                cpu: CPUMonitor.Sample(user: cpuCurve[i] * 0.7, system: cpuCurve[i] * 0.3,
                                       idle: 100 - cpuCurve[i]),
                memory: MemoryMonitor.Sample(usedBytes: UInt64(memCurve[i] / 100 * 16 * 1024 * 1024 * 1024),
                                             totalBytes: UInt64(16 * 1024 * 1024 * 1024)),
                network: NetworkMonitor.Sample(downloadBytesPerSec: netCurve[i],
                                               uploadBytesPerSec: netCurve[i] * 0.2),
                disk: nil, temperature: nil, power: nil
            )
        }
    }

    private static func writePNG(view: NSView, to url: URL) throws {
        // Render at 2× for retina-crisp screenshots in the README.
        let scale: CGFloat = 2
        let pixelSize = NSSize(width: view.bounds.width * scale,
                               height: view.bounds.height * scale)
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(pixelSize.width),
            pixelsHigh: Int(pixelSize.height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            throw NSError(domain: "screenshots", code: 1)
        }
        rep.size = view.bounds.size

        NSGraphicsContext.saveGraphicsState()
        guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else {
            NSGraphicsContext.restoreGraphicsState()
            throw NSError(domain: "screenshots", code: 2)
        }
        NSGraphicsContext.current = ctx
        // Fill with the standard window background so popover/settings look natural
        // when the README renders them on light/dark theme.
        NSColor.windowBackgroundColor.setFill()
        view.bounds.fill()
        view.displayIgnoringOpacity(view.bounds, in: ctx)
        NSGraphicsContext.restoreGraphicsState()

        guard let data = rep.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "screenshots", code: 3)
        }
        try data.write(to: url)
        print("✓ \(url.lastPathComponent)")
    }
}
