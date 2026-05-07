import AppKit

final class StatsPopoverController: NSViewController {
    private let cpuLabel = StatsPopoverController.makeValueLabel()
    private let cpuBreakdown = StatsPopoverController.makeSecondaryLabel()
    private let cpuSparkline = SparklineView(capacity: 60)

    private let memLabel = StatsPopoverController.makeValueLabel()
    private let memBreakdown = StatsPopoverController.makeSecondaryLabel()

    private let downLabel = StatsPopoverController.makeValueLabel()
    private let upLabel = StatsPopoverController.makeValueLabel()
    private let netSparkline = SparklineView(capacity: 60)

    private let diskReadLabel = StatsPopoverController.makeValueLabel()
    private let diskWriteLabel = StatsPopoverController.makeValueLabel()

    private let versionLabel: NSTextField = {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
        let label = NSTextField(labelWithString: "MacPulse v\(v)")
        label.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        label.textColor = .tertiaryLabelColor
        return label
    }()

    private let quitButton = NSButton(title: "Quit", target: nil, action: nil)

    override func loadView() {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 280, height: 360))

        cpuSparkline.fixedMaxValue = 100  // CPU 是百分比
        cpuSparkline.lineColor = .systemBlue
        cpuSparkline.fillColor = NSColor.systemBlue.withAlphaComponent(0.18)
        cpuSparkline.translatesAutoresizingMaskIntoConstraints = false
        cpuSparkline.heightAnchor.constraint(equalToConstant: 36).isActive = true

        netSparkline.lineColor = .systemGreen
        netSparkline.fillColor = NSColor.systemGreen.withAlphaComponent(0.18)
        netSparkline.translatesAutoresizingMaskIntoConstraints = false
        netSparkline.heightAnchor.constraint(equalToConstant: 36).isActive = true

        let cpuBlock = section("CPU", primary: cpuLabel, secondary: cpuBreakdown, chart: cpuSparkline)
        let memBlock = section("Memory", primary: memLabel, secondary: memBreakdown)
        let netBlock = section(
            "Network",
            rows: [
                row(symbol: "↓", value: downLabel),
                row(symbol: "↑", value: upLabel)
            ],
            chart: netSparkline
        )
        let diskBlock = section(
            "Disk",
            rows: [
                row(symbol: "R", value: diskReadLabel),
                row(symbol: "W", value: diskWriteLabel)
            ]
        )

        quitButton.bezelStyle = .rounded
        quitButton.target = self
        quitButton.action = #selector(quit)

        let footer = NSStackView(views: [versionLabel, NSView(), quitButton])
        footer.orientation = .horizontal
        footer.alignment = .centerY

        let stack = NSStackView(views: [cpuBlock, memBlock, netBlock, diskBlock, footer])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 14, left: 16, bottom: 14, right: 16)
        stack.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            footer.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -32)
        ])

        self.view = container
    }

    func update(cpu: CPUMonitor.Sample,
                memory: MemoryMonitor.Sample,
                network: NetworkMonitor.Sample,
                disk: DiskMonitor.Sample) {
        cpuLabel.stringValue = String(format: "%.1f %%", cpu.total)
        cpuBreakdown.stringValue = String(format: "user %.1f %% · system %.1f %% · idle %.1f %%",
                                          cpu.user, cpu.system, cpu.idle)
        cpuSparkline.append(cpu.total)

        memLabel.stringValue = String(format: "%.1f %%", memory.usagePercent)
        memBreakdown.stringValue = "\(ByteFormatter.size(memory.usedBytes)) of \(ByteFormatter.size(memory.totalBytes))"

        downLabel.stringValue = ByteFormatter.rate(network.downloadBytesPerSec)
        upLabel.stringValue   = ByteFormatter.rate(network.uploadBytesPerSec)
        netSparkline.append(network.downloadBytesPerSec + network.uploadBytesPerSec)

        diskReadLabel.stringValue  = ByteFormatter.rate(disk.readBytesPerSec)
        diskWriteLabel.stringValue = ByteFormatter.rate(disk.writeBytesPerSec)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    // MARK: - Layout helpers

    private func section(_ title: String,
                         primary: NSTextField,
                         secondary: NSTextField,
                         chart: SparklineView? = nil) -> NSStackView {
        var views: [NSView] = [sectionTitle(title), primary, secondary]
        if let chart { views.append(chart) }
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 2
        stack.translatesAutoresizingMaskIntoConstraints = false
        if let chart {
            chart.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        return stack
    }

    private func section(_ title: String, rows: [NSView], chart: SparklineView? = nil) -> NSStackView {
        var views: [NSView] = [sectionTitle(title)]
        views.append(contentsOf: rows)
        if let chart { views.append(chart) }
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        if let chart {
            chart.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        return stack
    }

    private func row(symbol: String, value: NSTextField) -> NSView {
        let symbolLabel = NSTextField(labelWithString: symbol)
        symbolLabel.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .semibold)
        symbolLabel.textColor = .secondaryLabelColor
        symbolLabel.widthAnchor.constraint(equalToConstant: 16).isActive = true

        let stack = NSStackView(views: [symbolLabel, value])
        stack.orientation = .horizontal
        stack.spacing = 6
        return stack
    }

    private func sectionTitle(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text.uppercased())
        label.font = NSFont.systemFont(ofSize: 10, weight: .semibold)
        label.textColor = .secondaryLabelColor
        return label
    }

    private static func makeValueLabel() -> NSTextField {
        let label = NSTextField(labelWithString: "—")
        label.font = NSFont.monospacedDigitSystemFont(ofSize: 17, weight: .semibold)
        label.textColor = .labelColor
        return label
    }

    private static func makeSecondaryLabel() -> NSTextField {
        let label = NSTextField(labelWithString: "")
        label.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        label.textColor = .secondaryLabelColor
        return label
    }
}
