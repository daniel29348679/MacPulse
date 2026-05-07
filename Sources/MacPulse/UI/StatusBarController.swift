import AppKit

final class StatusBarController: NSObject {
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private let popoverController = StatsPopoverController()

    private let cpu = CPUMonitor()
    private let memory = MemoryMonitor()
    private let network = NetworkMonitor()
    private let disk = DiskMonitor()
    private let temperature = TemperatureMonitor()
    private let power = PowerMonitor()

    private var timer: Timer?
    private var screenAsleep = false

    // 暫存最後一次樣本，用於 popover 重新整理（即使該 metric 不在 menu bar）
    private var lastCPU: CPUMonitor.Sample?
    private var lastMemory: MemoryMonitor.Sample?
    private var lastNetwork: NetworkMonitor.Sample?
    private var lastDisk: DiskMonitor.Sample?
    private var lastTemperature: TemperatureMonitor.Sample?
    private var lastPower: PowerMonitor.Sample?

    override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        if let button = statusItem.button {
            button.target = self
            button.action = #selector(handleClick(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        popover.behavior = .transient
        popover.contentViewController = popoverController
        popoverController.onOpenSettings = { [weak self] in
            self?.popover.performClose(nil)
            self?.openSettings()
        }
        popoverController.onQuit = { NSApp.terminate(nil) }

        // 第一次取基準
        _ = cpu.sample()
        _ = network.sample()
        _ = disk.sample()

        renderEmpty()
        startTimer()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(settingsChanged),
            name: .macPulseSettingsChanged,
            object: nil
        )

        // Restart the timer when the user toggles Low Power Mode so the
        // throttled interval (effectiveInterval()) takes effect immediately.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(powerStateChanged),
            name: NSNotification.Name.NSProcessInfoPowerStateDidChange,
            object: nil
        )

        // Pause sampling entirely while the display is asleep — the user
        // can't see the menu bar, and waking the CPU once a second just to
        // recompute invisible numbers is the single biggest battery cost
        // a status-bar app like this can rack up overnight.
        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(self, selector: #selector(screensWillSleep),
                              name: NSWorkspace.screensDidSleepNotification, object: nil)
        workspace.addObserver(self, selector: #selector(screensDidWake),
                              name: NSWorkspace.screensDidWakeNotification, object: nil)
    }

    deinit {
        timer?.invalidate()
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    // MARK: - Sampling

    private func startTimer() {
        timer?.invalidate()
        guard !screenAsleep else { return }   // resume() runs startTimer() again on wake.
        let interval = effectiveInterval()
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            self?.tick()
        }
        // Letting the OS slip the fire time by ±10% lets it coalesce our wakeup
        // with other scheduled work — the single biggest power win for a 1-Hz
        // status bar app, since idle wakeups dominate "Energy Impact" in
        // Activity Monitor far more than CPU%.
        timer.tolerance = interval * 0.1
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// Configured interval, throttled to ≥5 s in Low Power Mode so the user's
    /// explicit "save battery" choice is honoured even if MacPulse is set to 1 s.
    private func effectiveInterval() -> TimeInterval {
        let configured = Settings.shared.updateInterval
        if ProcessInfo.processInfo.isLowPowerModeEnabled {
            return max(configured, 5.0)
        }
        return configured
    }

    @objc private func settingsChanged() {
        startTimer()           // interval 可能變了
        popoverController.applyVisibility()
        popoverController.applySparklineCapacity()
        renderMenuBar()        // 用最後一次樣本重繪
    }

    @objc private func powerStateChanged() {
        // Posted on a background queue — bounce to main before touching the timer.
        DispatchQueue.main.async { [weak self] in self?.startTimer() }
    }

    @objc private func screensWillSleep() {
        screenAsleep = true
        timer?.invalidate()
        timer = nil
    }

    @objc private func screensDidWake() {
        screenAsleep = false
        // Immediate sample so the menu bar doesn't show stale numbers from
        // before sleep while the user waits up to `interval` for the timer.
        tick()
        startTimer()
    }

    private func tick() {
        lastCPU = cpu.sample()
        lastMemory = memory.sample()
        lastNetwork = network.sample()
        lastDisk = disk.sample()
        lastTemperature = temperature.sample()
        lastPower = power.sample()

        renderMenuBar()

        // Always feed sparkline buffers (so opening the popover later shows
        // a populated chart), but skip the relatively expensive text-label
        // updates while the popover is hidden.
        let popoverShown = popover.isShown
        popoverController.appendSamples(cpu: lastCPU,
                                        memory: lastMemory,
                                        network: lastNetwork)
        if popoverShown {
            popoverController.update(cpu: lastCPU,
                                     memory: lastMemory,
                                     network: lastNetwork,
                                     disk: lastDisk,
                                     temperature: lastTemperature,
                                     power: lastPower)
        }
    }

    // MARK: - Menu bar rendering

    private func renderEmpty() {
        guard let button = statusItem.button else { return }
        button.title = ""
        if let img = NSImage(systemSymbolName: "waveform.path.ecg",
                             accessibilityDescription: "MacPulse") {
            button.image = img.withSymbolConfiguration(.init(pointSize: 13, weight: .medium))
        }
    }

    private func renderMenuBar() {
        guard let button = statusItem.button else { return }
        let visible = Settings.shared.menuBarMetrics

        if visible.isEmpty {
            renderEmpty()
            return
        }
        button.image = nil

        // 上排：CPU / RAM / Temperature 這類「狀態指標」
        var topParts: [String] = []
        if visible.contains(.cpu), let s = lastCPU {
            topParts.append(String(format: "CPU %2.0f%%", s.total))
        }
        if visible.contains(.memory), let s = lastMemory {
            topParts.append(String(format: "RAM %2.0f%%", s.usagePercent))
        }
        if visible.contains(.temperature), let s = lastTemperature {
            if let c = s.celsius {
                topParts.append(String(format: "%.0f°", c))
            } else {
                topParts.append(s.level.compactSymbol)
            }
        }
        if visible.contains(.power), let s = lastPower, let watts = s.watts {
            switch s.state {
            case .charging:    topParts.append(String(format: "↑%.0fW", watts))
            case .discharging: topParts.append(String(format: "↓%.0fW", watts))
            case .ac, .unavailable: break
            }
        }

        // 下排：Network / Disk 這類「速率」
        var bottomParts: [String] = []
        if visible.contains(.network), let s = lastNetwork {
            bottomParts.append("↓ \(compactRate(s.downloadBytesPerSec))")
            bottomParts.append("↑ \(compactRate(s.uploadBytesPerSec))")
        }
        if visible.contains(.disk), let s = lastDisk {
            bottomParts.append("R \(compactRate(s.readBytesPerSec))")
            bottomParts.append("W \(compactRate(s.writeBytesPerSec))")
        }

        let topLine = topParts.joined(separator: "  ")
        let bottomLine = bottomParts.joined(separator: "  ")
        let twoLines = !topLine.isEmpty && !bottomLine.isEmpty

        // NSStatusBarButton's attributedTitle path is hit-or-miss for vertical
        // centering across font sizes — render to an NSImage ourselves so the
        // glyphs sit exactly in the middle of the menu bar height.
        button.title = ""
        button.attributedTitle = NSAttributedString()
        button.image = renderTitleImage(topLine: topLine, bottomLine: bottomLine, twoLines: twoLines)
    }

    private func renderTitleImage(topLine: String, bottomLine: String, twoLines: Bool) -> NSImage {
        let fontSize: CGFloat = twoLines ? 10 : 12
        let font = NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .medium)
        let lineHeight: CGFloat = twoLines ? 10.5 : 14
        // Use the system's reported menu bar thickness — on stock macOS this is
        // 22pt, but accessibility / external displays can change it.
        let imageHeight: CGFloat = NSStatusBar.system.thickness

        // Pure black + alpha so isTemplate = true lets the menu bar invert it
        // for dark mode / selection state automatically.
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.black
        ]

        let lines: [NSAttributedString]
        if twoLines {
            lines = [NSAttributedString(string: topLine, attributes: attrs),
                     NSAttributedString(string: bottomLine, attributes: attrs)]
        } else {
            let single = topLine.isEmpty ? bottomLine : topLine
            lines = [NSAttributedString(string: single, attributes: attrs)]
        }

        let widths = lines.map { $0.size().width }
        let imageWidth = (widths.max() ?? 0).rounded(.up) + 4   // small right padding

        let image = NSImage(size: NSSize(width: imageWidth, height: imageHeight))
        image.lockFocusFlipped(false)
        defer { image.unlockFocus() }

        let totalTextHeight = CGFloat(lines.count) * lineHeight
        // Optical centering: nudge down a hair because system fonts have a
        // slightly heavier ascender than descender, which makes geometric
        // centering look top-heavy.
        let topY = (imageHeight - totalTextHeight) / 2 - 1

        for (i, line) in lines.enumerated() {
            let lineWidth = widths[i]
            let x = imageWidth - lineWidth - 2   // right-align with 2 pt right margin
            let y = topY + CGFloat(lines.count - 1 - i) * lineHeight
            line.draw(at: NSPoint(x: x, y: y))
        }

        // template = true lets the menu bar invert the colors automatically
        // when the menu bar is in dark mode / selected.
        image.isTemplate = true
        return image
    }

    private func compactRate(_ bps: Double) -> String {
        let v = max(0, bps)
        if v < 1024 {
            return String(format: "%3.0fB", v)
        } else if v < 1024 * 1024 {
            return String(format: "%3.0fK", v / 1024)
        } else if v < 1024 * 1024 * 1024 {
            return String(format: "%4.1fM", v / (1024 * 1024))
        } else {
            return String(format: "%4.2fG", v / (1024 * 1024 * 1024))
        }
    }

    // MARK: - Click handling

    @objc private func handleClick(_ sender: AnyObject?) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            showContextMenu()
        } else {
            togglePopover(sender)
        }
    }

    private func togglePopover(_ sender: AnyObject?) {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            // Refresh text labels with the most recent cached samples before
            // showing — tick() skips this work while the popover is hidden.
            popoverController.update(cpu: lastCPU,
                                     memory: lastMemory,
                                     network: lastNetwork,
                                     disk: lastDisk,
                                     temperature: lastTemperature,
                                     power: lastPower)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func showContextMenu() {
        let menu = NSMenu()

        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        let intervalRoot = NSMenuItem(title: "Update Interval", action: nil, keyEquivalent: "")
        let intervalSubmenu = NSMenu()
        let current = Settings.shared.updateInterval
        for interval in Settings.allowedIntervals {
            let item = NSMenuItem(
                title: Settings.intervalLabel(interval),
                action: #selector(selectInterval(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = interval
            item.state = (interval == current) ? .on : .off
            intervalSubmenu.addItem(item)
        }
        intervalRoot.submenu = intervalSubmenu
        menu.addItem(intervalRoot)

        menu.addItem(.separator())

        let about = NSMenuItem(title: "View on GitHub", action: #selector(openRepo), keyEquivalent: "")
        about.target = self
        menu.addItem(about)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit MacPulse", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func selectInterval(_ sender: NSMenuItem) {
        guard let interval = sender.representedObject as? TimeInterval else { return }
        Settings.shared.updateInterval = interval
    }

    @objc private func openSettings() {
        SettingsWindowController.shared.show()
    }

    @objc private func openRepo() {
        if let url = URL(string: "https://github.com/daniel29348679/MacPulse") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
