import AppKit

final class StatsPopoverController: NSViewController {
    private let cpuLabel = StatsPopoverController.makeValueLabel()
    private let cpuBreakdown = StatsPopoverController.makeSecondaryLabel()
    private let memLabel = StatsPopoverController.makeValueLabel()
    private let memBreakdown = StatsPopoverController.makeSecondaryLabel()
    private let downLabel = StatsPopoverController.makeValueLabel()
    private let upLabel = StatsPopoverController.makeValueLabel()
    private let quitButton = NSButton(title: "Quit MacPulse", target: nil, action: nil)

    override func loadView() {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 260, height: 220))

        let title = NSTextField(labelWithString: "MacPulse")
        title.font = NSFont.systemFont(ofSize: 14, weight: .semibold)
        title.textColor = .labelColor

        let cpuTitle = StatsPopoverController.sectionTitle("CPU")
        let memTitle = StatsPopoverController.sectionTitle("Memory")
        let netTitle = StatsPopoverController.sectionTitle("Network")

        let downRow = StatsPopoverController.row(symbol: "↓", value: downLabel)
        let upRow   = StatsPopoverController.row(symbol: "↑", value: upLabel)

        quitButton.bezelStyle = .rounded
        quitButton.target = self
        quitButton.action = #selector(quit)

        let stack = NSStackView(views: [
            title,
            cpuTitle, cpuLabel, cpuBreakdown,
            memTitle, memLabel, memBreakdown,
            netTitle, downRow, upRow,
            NSView(),
            quitButton
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 4
        stack.edgeInsets = NSEdgeInsets(top: 14, left: 16, bottom: 14, right: 16)
        stack.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])

        self.view = container
    }

    func update(cpu: CPUMonitor.Sample, memory: MemoryMonitor.Sample, network: NetworkMonitor.Sample) {
        cpuLabel.stringValue = String(format: "%.1f %%", cpu.total)
        cpuBreakdown.stringValue = String(format: "user %.1f %% · system %.1f %% · idle %.1f %%",
                                          cpu.user, cpu.system, cpu.idle)

        memLabel.stringValue = String(format: "%.1f %%", memory.usagePercent)
        memBreakdown.stringValue = "\(ByteFormatter.size(memory.usedBytes)) of \(ByteFormatter.size(memory.totalBytes))"

        downLabel.stringValue = ByteFormatter.rate(network.downloadBytesPerSec)
        upLabel.stringValue   = ByteFormatter.rate(network.uploadBytesPerSec)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    // MARK: - Helpers

    private static func makeValueLabel() -> NSTextField {
        let label = NSTextField(labelWithString: "—")
        label.font = NSFont.monospacedDigitSystemFont(ofSize: 18, weight: .semibold)
        label.textColor = .labelColor
        return label
    }

    private static func makeSecondaryLabel() -> NSTextField {
        let label = NSTextField(labelWithString: "")
        label.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        label.textColor = .secondaryLabelColor
        return label
    }

    private static func sectionTitle(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text.uppercased())
        label.font = NSFont.systemFont(ofSize: 10, weight: .semibold)
        label.textColor = .secondaryLabelColor
        return label
    }

    private static func row(symbol: String, value: NSTextField) -> NSView {
        let symbolLabel = NSTextField(labelWithString: symbol)
        symbolLabel.font = NSFont.systemFont(ofSize: 16, weight: .medium)
        symbolLabel.textColor = .secondaryLabelColor

        let stack = NSStackView(views: [symbolLabel, value])
        stack.orientation = .horizontal
        stack.spacing = 8
        return stack
    }
}
