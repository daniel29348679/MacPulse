import AppKit

final class StatusBarController: NSObject {
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private let popoverController = StatsPopoverController()

    private let cpu = CPUMonitor()
    private let memory = MemoryMonitor()
    private let network = NetworkMonitor()
    private let disk = DiskMonitor()

    private var timer: Timer?

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

        // 立刻取一次基準樣本，避免第一次顯示是 0
        _ = cpu.sample()
        _ = network.sample()
        _ = disk.sample()

        render(cpuPercent: 0,
               memPercent: memory.sample().usagePercent,
               down: 0, up: 0)

        startTimer()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(intervalChanged),
            name: .macPulseIntervalChanged,
            object: nil
        )
    }

    deinit {
        timer?.invalidate()
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Sampling

    private func startTimer() {
        timer?.invalidate()
        let interval = Settings.shared.updateInterval
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    @objc private func intervalChanged() {
        startTimer()
    }

    private func tick() {
        let cpuSample = cpu.sample()
        let memSample = memory.sample()
        let netSample = network.sample()
        let diskSample = disk.sample()

        render(cpuPercent: cpuSample.total,
               memPercent: memSample.usagePercent,
               down: netSample.downloadBytesPerSec,
               up: netSample.uploadBytesPerSec)

        popoverController.update(cpu: cpuSample,
                                 memory: memSample,
                                 network: netSample,
                                 disk: diskSample)
    }

    // MARK: - Rendering

    private func render(cpuPercent: Double, memPercent: Double, down: Double, up: Double) {
        guard let button = statusItem.button else { return }

        let topLine = String(format: "CPU %2.0f%%  RAM %2.0f%%", cpuPercent, memPercent)
        let bottomLine = "↓ \(compactRate(down))  ↑ \(compactRate(up))"

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .right
        paragraph.maximumLineHeight = 11
        paragraph.minimumLineHeight = 11

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .medium),
            .paragraphStyle: paragraph,
            .foregroundColor: NSColor.labelColor
        ]

        button.attributedTitle = NSAttributedString(
            string: "\(topLine)\n\(bottomLine)",
            attributes: attributes
        )
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
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func showContextMenu() {
        let menu = NSMenu()

        let intervalRoot = NSMenuItem(title: "Update Interval", action: nil, keyEquivalent: "")
        let intervalSubmenu = NSMenu()
        let current = Settings.shared.updateInterval
        for interval in Settings.allowedIntervals {
            let item = NSMenuItem(
                title: String(format: "%.1f s", interval),
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

        let about = NSMenuItem(title: "About MacPulse", action: #selector(openRepo), keyEquivalent: "")
        about.target = self
        menu.addItem(about)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit MacPulse", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        // 顯示後立刻重設 menu，否則下次左鍵點擊會誤觸 menu
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func selectInterval(_ sender: NSMenuItem) {
        guard let interval = sender.representedObject as? TimeInterval else { return }
        Settings.shared.updateInterval = interval
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
