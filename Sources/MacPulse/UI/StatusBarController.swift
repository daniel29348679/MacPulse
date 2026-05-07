import AppKit

final class StatusBarController {
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private let popoverController = StatsPopoverController()

    private let cpu = CPUMonitor()
    private let memory = MemoryMonitor()
    private let network = NetworkMonitor()

    private var timer: Timer?
    private let updateInterval: TimeInterval = 1.5

    init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.action = #selector(togglePopover(_:))
            button.target = self
        }

        popover.behavior = .transient
        popover.contentViewController = popoverController

        // 立刻取一次基準樣本，避免第一次顯示是 0
        _ = cpu.sample()
        _ = network.sample()

        // 初始顯示
        render(cpuPercent: 0,
               memPercent: memory.sample().usagePercent,
               down: 0, up: 0)

        startTimer()
    }

    deinit {
        timer?.invalidate()
    }

    private func startTimer() {
        let timer = Timer(timeInterval: updateInterval, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func tick() {
        let cpuSample = cpu.sample()
        let memSample = memory.sample()
        let netSample = network.sample()

        render(cpuPercent: cpuSample.total,
               memPercent: memSample.usagePercent,
               down: netSample.downloadBytesPerSec,
               up: netSample.uploadBytesPerSec)

        popoverController.update(cpu: cpuSample, memory: memSample, network: netSample)
    }

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

    /// 給狀態列用的緊湊版速率（沒有 /s 後綴以節省空間）
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

    @objc private func togglePopover(_ sender: AnyObject?) {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
}
