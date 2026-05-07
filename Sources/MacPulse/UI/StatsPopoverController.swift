import AppKit

final class StatsPopoverController: NSViewController {

    // MARK: - Section views (kept around to toggle isHidden)

    private var sections: [Metric: NSView] = [:]

    // CPU
    private let cpuValueLabel = StatsPopoverController.makeValueLabel()
    private let cpuBreakdown = StatsPopoverController.makeSecondaryLabel()
    private let cpuSparkline = SparklineView(capacity: 60)

    // Memory
    private let memValueLabel = StatsPopoverController.makeValueLabel()
    private let memBreakdown = StatsPopoverController.makeSecondaryLabel()
    private let memSparkline = SparklineView(capacity: 60)

    // Network
    private let downLabel = StatsPopoverController.makeRateLabel()
    private let upLabel = StatsPopoverController.makeRateLabel()
    private let netSparkline = SparklineView(capacity: 60)

    // Disk
    private let diskReadLabel = StatsPopoverController.makeRateLabel()
    private let diskWriteLabel = StatsPopoverController.makeRateLabel()

    // Temperature
    private let tempLabel = StatsPopoverController.makeValueLabel()
    private let tempBreakdown = StatsPopoverController.makeSecondaryLabel()
    private let tempDot = ColorDotView()

    // Footer
    private let versionLabel: NSTextField = {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
        let label = NSTextField(labelWithString: "v\(v)")
        label.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        label.textColor = .tertiaryLabelColor
        return label
    }()

    var onOpenSettings: (() -> Void)?
    var onQuit: (() -> Void)?

    private lazy var rootStack: NSStackView = NSStackView()

    override func loadView() {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false

        // Header
        let title = NSTextField(labelWithString: "MacPulse")
        title.font = NSFont.systemFont(ofSize: 14, weight: .bold)
        title.textColor = .labelColor

        let settingsButton = iconButton(symbol: "gearshape", action: #selector(openSettings))
        settingsButton.toolTip = "Settings"
        let quitButton = iconButton(symbol: "power", action: #selector(quitApp))
        quitButton.toolTip = "Quit MacPulse"

        let header = NSStackView(views: [title, NSView(), settingsButton, quitButton])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 4

        // CPU section
        cpuSparkline.fixedMaxValue = 100
        cpuSparkline.lineColor = .systemBlue
        cpuSparkline.fillColor = NSColor.systemBlue.withAlphaComponent(0.18)
        cpuSparkline.heightAnchor.constraint(equalToConstant: 30).isActive = true

        let cpuRow = headerRow(metric: .cpu, valueView: cpuValueLabel)
        let cpuSection = stack([cpuRow, cpuBreakdown, cpuSparkline], spacing: 4)
        sections[.cpu] = cpuSection

        // Memory
        memSparkline.fixedMaxValue = 100
        memSparkline.lineColor = .systemPurple
        memSparkline.fillColor = NSColor.systemPurple.withAlphaComponent(0.18)
        memSparkline.heightAnchor.constraint(equalToConstant: 30).isActive = true

        let memRow = headerRow(metric: .memory, valueView: memValueLabel)
        let memSection = stack([memRow, memBreakdown, memSparkline], spacing: 4)
        sections[.memory] = memSection

        // Network
        netSparkline.lineColor = .systemGreen
        netSparkline.fillColor = NSColor.systemGreen.withAlphaComponent(0.18)
        netSparkline.heightAnchor.constraint(equalToConstant: 30).isActive = true

        let downRow = labelledRow(symbol: "↓", value: downLabel)
        let upRow = labelledRow(symbol: "↑", value: upLabel)
        let netHeader = headerRow(metric: .network, valueView: nil)
        let netRates = NSStackView(views: [downRow, NSView(), upRow])
        netRates.orientation = .horizontal
        netRates.spacing = 12
        let netSection = stack([netHeader, netRates, netSparkline], spacing: 4)
        sections[.network] = netSection

        // Disk
        let readRow = labelledRow(symbol: "R", value: diskReadLabel)
        let writeRow = labelledRow(symbol: "W", value: diskWriteLabel)
        let diskHeader = headerRow(metric: .disk, valueView: nil)
        let diskRates = NSStackView(views: [readRow, NSView(), writeRow])
        diskRates.orientation = .horizontal
        diskRates.spacing = 12
        let diskSection = stack([diskHeader, diskRates], spacing: 4)
        sections[.disk] = diskSection

        // Temperature
        tempDot.translatesAutoresizingMaskIntoConstraints = false
        tempDot.widthAnchor.constraint(equalToConstant: 10).isActive = true
        tempDot.heightAnchor.constraint(equalToConstant: 10).isActive = true

        let tempValueRow = NSStackView(views: [tempLabel, tempDot])
        tempValueRow.orientation = .horizontal
        tempValueRow.spacing = 6
        tempValueRow.alignment = .centerY

        let tempHeader = headerRow(metric: .temperature, valueView: tempValueRow)
        let tempSection = stack([tempHeader, tempBreakdown], spacing: 4)
        sections[.temperature] = tempSection

        // Compose root stack with section + divider for each
        var rootSubviews: [NSView] = [header, divider()]
        for metric in Metric.allCases {
            if let section = sections[metric] {
                rootSubviews.append(section)
                rootSubviews.append(divider())
            }
        }

        let footerRow = NSStackView(views: [versionLabel, NSView()])
        footerRow.orientation = .horizontal
        rootSubviews.append(footerRow)

        rootStack = NSStackView(views: rootSubviews)
        rootStack.orientation = .vertical
        rootStack.alignment = .leading
        rootStack.spacing = 10
        rootStack.edgeInsets = NSEdgeInsets(top: 14, left: 16, bottom: 12, right: 16)
        rootStack.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(rootStack)
        NSLayoutConstraint.activate([
            rootStack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            rootStack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            rootStack.topAnchor.constraint(equalTo: container.topAnchor),
            rootStack.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])

        // 撐滿到 stack 寬度
        for view in rootSubviews {
            view.translatesAutoresizingMaskIntoConstraints = false
            view.widthAnchor.constraint(equalTo: rootStack.widthAnchor, constant: -32).isActive = true
        }

        applyVisibility()
        applySparklineCapacity()
        self.view = container
        adjustPreferredSize()
    }

    /// 依設定（採樣間隔 / 折線時間長度）調整每條 sparkline 的 buffer 容量
    func applySparklineCapacity() {
        let cap = Settings.shared.sparklineCapacity
        cpuSparkline.setCapacity(cap)
        memSparkline.setCapacity(cap)
        netSparkline.setCapacity(cap)
    }

    func applyVisibility() {
        let visible = Settings.shared.popoverMetrics
        for (metric, view) in sections {
            view.isHidden = !visible.contains(metric)
            // 鄰接的 divider 也要連動 — 找到該 view 後面那個 divider
            if let stack = view.superview as? NSStackView,
               let idx = stack.arrangedSubviews.firstIndex(of: view),
               idx + 1 < stack.arrangedSubviews.count {
                let next = stack.arrangedSubviews[idx + 1]
                if next is NSBox { next.isHidden = !visible.contains(metric) }
            }
        }
        adjustPreferredSize()
    }

    private func adjustPreferredSize() {
        rootStack.layoutSubtreeIfNeeded()
        let size = rootStack.fittingSize
        preferredContentSize = NSSize(width: 280, height: max(size.height, 80))
    }

    // MARK: - Sample updates

    func update(cpu: CPUMonitor.Sample?,
                memory: MemoryMonitor.Sample?,
                network: NetworkMonitor.Sample?,
                disk: DiskMonitor.Sample?,
                temperature: TemperatureMonitor.Sample?) {

        if let cpu {
            cpuValueLabel.stringValue = String(format: "%.1f %%", cpu.total)
            cpuBreakdown.stringValue = String(format: "user %.1f · system %.1f · idle %.1f",
                                              cpu.user, cpu.system, cpu.idle)
            cpuSparkline.append(cpu.total)
        }

        if let memory {
            memValueLabel.stringValue = String(format: "%.1f %%", memory.usagePercent)
            memBreakdown.stringValue = "\(ByteFormatter.size(memory.usedBytes)) / \(ByteFormatter.size(memory.totalBytes))"
            memSparkline.append(memory.usagePercent)
        }

        if let network {
            downLabel.stringValue = ByteFormatter.rate(network.downloadBytesPerSec)
            upLabel.stringValue   = ByteFormatter.rate(network.uploadBytesPerSec)
            netSparkline.append(network.downloadBytesPerSec + network.uploadBytesPerSec)
        }

        if let disk {
            diskReadLabel.stringValue  = ByteFormatter.rate(disk.readBytesPerSec)
            diskWriteLabel.stringValue = ByteFormatter.rate(disk.writeBytesPerSec)
        }

        if let temperature {
            if let c = temperature.celsius {
                tempLabel.stringValue = String(format: "%.0f °C", c)
                tempBreakdown.stringValue = temperature.level.label.lowercased()
            } else {
                tempLabel.stringValue = temperature.level.label
                tempBreakdown.stringValue = "thermal pressure (no sensor reading)"
            }
            tempDot.color = temperature.level.color
        }
    }

    // MARK: - Action plumbing

    @objc private func openSettings() { onOpenSettings?() }
    @objc private func quitApp()      { onQuit?() }

    // MARK: - View helpers

    private func headerRow(metric: Metric, valueView: NSView?) -> NSStackView {
        let icon = NSImageView()
        if let img = NSImage(systemSymbolName: metric.symbolName, accessibilityDescription: nil) {
            icon.image = img.withSymbolConfiguration(.init(pointSize: 13, weight: .medium))
        }
        icon.contentTintColor = .secondaryLabelColor
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.widthAnchor.constraint(equalToConstant: 18).isActive = true

        let title = NSTextField(labelWithString: metric.displayName.uppercased())
        title.font = NSFont.systemFont(ofSize: 10, weight: .semibold)
        title.textColor = .secondaryLabelColor

        var views: [NSView] = [icon, title, NSView()]
        if let valueView { views.append(valueView) }

        let row = NSStackView(views: views)
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 6
        return row
    }

    private func labelledRow(symbol: String, value: NSTextField) -> NSStackView {
        let symbolLabel = NSTextField(labelWithString: symbol)
        symbolLabel.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .semibold)
        symbolLabel.textColor = .secondaryLabelColor
        symbolLabel.widthAnchor.constraint(equalToConstant: 14).isActive = true

        let stack = NSStackView(views: [symbolLabel, value])
        stack.orientation = .horizontal
        stack.spacing = 4
        stack.alignment = .firstBaseline
        return stack
    }

    private func stack(_ views: [NSView], spacing: CGFloat) -> NSStackView {
        let s = NSStackView(views: views)
        s.orientation = .vertical
        s.alignment = .leading
        s.spacing = spacing
        return s
    }

    private func divider() -> NSBox {
        let box = NSBox()
        box.boxType = .separator
        return box
    }

    private func iconButton(symbol: String, action: Selector) -> NSButton {
        let button = NSButton()
        button.bezelStyle = .accessoryBarAction
        button.isBordered = false
        if let img = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) {
            button.image = img.withSymbolConfiguration(.init(pointSize: 13, weight: .medium))
        }
        button.target = self
        button.action = action
        button.contentTintColor = .secondaryLabelColor
        return button
    }

    // MARK: - Static factories

    private static func makeValueLabel() -> NSTextField {
        let label = NSTextField(labelWithString: "—")
        label.font = NSFont.monospacedDigitSystemFont(ofSize: 14, weight: .semibold)
        label.textColor = .labelColor
        return label
    }

    private static func makeRateLabel() -> NSTextField {
        let label = NSTextField(labelWithString: "—")
        label.font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium)
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

/// 給溫度等級用的小色點
final class ColorDotView: NSView {
    var color: NSColor = .systemBlue { didSet { needsDisplay = true } }

    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 1, dy: 1)
        color.setFill()
        NSBezierPath(ovalIn: rect).fill()
    }
}
