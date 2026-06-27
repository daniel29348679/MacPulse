import AppKit

final class StatsPopoverController: NSViewController {

    // MARK: - Section views (kept around to toggle isHidden)

    private var sections: [Metric: NSView] = [:]
    private let scrollView: NSScrollView = {
        let view = NSScrollView()
        view.drawsBackground = false
        view.borderType = .noBorder
        view.hasVerticalScroller = true
        view.autohidesScrollers = true
        view.verticalScrollElasticity = .allowed
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    private let scrollDocumentView = FlippedDocumentView()
    private var preferredScreen: NSScreen?
    private let emptyStateView: NSStackView = {
        let title = NSTextField(labelWithString: "No metrics selected")
        title.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        title.textColor = .labelColor
        title.alignment = .center

        let detail = NSTextField(labelWithString: "Use Settings to choose what appears here.")
        detail.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        detail.textColor = .secondaryLabelColor
        detail.alignment = .center
        detail.maximumNumberOfLines = 2

        let stack = NSStackView(views: [title, detail])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 4
        stack.edgeInsets = NSEdgeInsets(top: 14, left: 0, bottom: 14, right: 0)
        stack.setAccessibilityLabel("No metrics selected. Use Settings to choose what appears in the popover.")
        return stack
    }()
    private let emptyStateDivider: NSBox = {
        let box = NSBox()
        box.boxType = .separator
        return box
    }()

    // CPU
    private let cpuValueLabel = StatsPopoverController.makeValueLabel()
    private let cpuBreakdown = StatsPopoverController.makeSecondaryLabel()
    private let cpuSparkline = SparklineView(capacity: 60)

    // GPU
    private let gpuValueLabel = StatsPopoverController.makeValueLabel()
    private let gpuBreakdown = StatsPopoverController.makeSecondaryLabel()
    private let gpuSparkline = SparklineView(capacity: 60)

    // Top processes (within the CPU section)
    private let processesHeaderButton: NSButton = {
        let button = NSButton(title: "▼  TOP PROCESSES", target: nil, action: nil)
        button.bezelStyle = .accessoryBarAction
        button.isBordered = false
        button.alignment = .left
        button.font = NSFont.systemFont(ofSize: 10, weight: .semibold)
        button.contentTintColor = .secondaryLabelColor
        button.toolTip = "Click to collapse / expand"
        button.setAccessibilityLabel("Top processes")
        button.setAccessibilityHelp("Collapse or expand the top processes list.")
        return button
    }()
    private let processListStack: NSStackView = {
        let s = NSStackView()
        s.orientation = .vertical
        s.alignment = .leading
        s.spacing = 1
        return s
    }()
    private let moreProcessesButton: NSButton = {
        let button = NSButton(title: "More ▸", target: nil, action: nil)
        button.bezelStyle = .accessoryBarAction
        button.isBordered = false
        button.contentTintColor = .controlAccentColor
        button.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        button.toolTip = "Show additional processes"
        button.setAccessibilityLabel("Show additional processes")
        return button
    }()
    private var processRows: [ProcessRowControl] = []
    private var allProcesses: [ProcessMonitor.Entry] = []
    /// 由外部（StatusBarController）注入：執行 Quit / Force Kill 並回報結果。
    var processActionHandler: ((ProcessMonitor.Entry, ProcessAction) -> Void)?

    enum ProcessAction {
        case quit       // SIGTERM
        case forceKill  // SIGKILL
    }

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

    // Power
    private let powerLabel = StatsPopoverController.makeValueLabel()
    private let powerBreakdown = StatsPopoverController.makeSecondaryLabel()

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

        let settingsButton = iconButton(symbol: "gearshape",
                                        accessibilityLabel: "Open Settings",
                                        action: #selector(openSettings))
        settingsButton.toolTip = "Settings"
        let quitButton = iconButton(symbol: "power",
                                    accessibilityLabel: "Quit MacPulse",
                                    action: #selector(quitApp))
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

        moreProcessesButton.target = self
        moreProcessesButton.action = #selector(showMoreProcessesMenu(_:))
        processesHeaderButton.target = self
        processesHeaderButton.action = #selector(toggleProcessesCollapsed)

        let processesSection = stack([processesHeaderButton, processListStack, moreProcessesButton], spacing: 4)

        let cpuSection = stack([cpuRow, cpuBreakdown, cpuSparkline, processesSection], spacing: 4)
        sections[.cpu] = cpuSection

        // Process list 寬度跟著 CPU section 撐滿
        processListStack.translatesAutoresizingMaskIntoConstraints = false
        processListStack.widthAnchor.constraint(equalTo: processesSection.widthAnchor).isActive = true
        processesSection.translatesAutoresizingMaskIntoConstraints = false
        processesSection.widthAnchor.constraint(equalTo: cpuSection.widthAnchor).isActive = true
        processesHeaderButton.translatesAutoresizingMaskIntoConstraints = false
        processesHeaderButton.widthAnchor.constraint(equalTo: processesSection.widthAnchor).isActive = true

        rebuildProcessRows()
        applyProcessesCollapsedState()

        // GPU
        gpuSparkline.fixedMaxValue = 100
        gpuSparkline.lineColor = .systemTeal
        gpuSparkline.fillColor = NSColor.systemTeal.withAlphaComponent(0.18)
        gpuSparkline.heightAnchor.constraint(equalToConstant: 30).isActive = true

        let gpuRow = headerRow(metric: .gpu, valueView: gpuValueLabel)
        let gpuSection = stack([gpuRow, gpuBreakdown, gpuSparkline], spacing: 4)
        sections[.gpu] = gpuSection

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

        // Power
        let powerHeader = headerRow(metric: .power, valueView: powerLabel)
        let powerSection = stack([powerHeader, powerBreakdown], spacing: 4)
        sections[.power] = powerSection

        // Compose root stack with section + divider for each
        var rootSubviews: [NSView] = [header, divider()]
        for metric in Metric.allCases {
            if let section = sections[metric] {
                rootSubviews.append(section)
                rootSubviews.append(divider())
            }
        }
        rootSubviews.append(emptyStateView)
        rootSubviews.append(emptyStateDivider)

        let footerRow = NSStackView(views: [versionLabel, NSView()])
        footerRow.orientation = .horizontal
        rootSubviews.append(footerRow)

        rootStack = NSStackView(views: rootSubviews)
        rootStack.orientation = .vertical
        rootStack.alignment = .leading
        rootStack.spacing = 10
        rootStack.edgeInsets = NSEdgeInsets(top: 14, left: 16, bottom: 12, right: 16)
        rootStack.translatesAutoresizingMaskIntoConstraints = false

        scrollDocumentView.translatesAutoresizingMaskIntoConstraints = false
        scrollDocumentView.addSubview(rootStack)
        scrollView.documentView = scrollDocumentView
        container.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: container.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor),

            scrollDocumentView.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            scrollDocumentView.trailingAnchor.constraint(equalTo: scrollView.contentView.trailingAnchor),
            scrollDocumentView.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
            scrollDocumentView.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),

            rootStack.leadingAnchor.constraint(equalTo: scrollDocumentView.leadingAnchor),
            rootStack.trailingAnchor.constraint(equalTo: scrollDocumentView.trailingAnchor),
            rootStack.topAnchor.constraint(equalTo: scrollDocumentView.topAnchor),
            rootStack.bottomAnchor.constraint(equalTo: scrollDocumentView.bottomAnchor)
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
        gpuSparkline.setCapacity(cap)
        memSparkline.setCapacity(cap)
        netSparkline.setCapacity(cap)
    }

    /// 設定的 topProcessCount 改變時呼叫，調整 inline row 數量。
    func applyProcessSettings() {
        rebuildProcessRows()
        applyProcessesCollapsedState()
        adjustPreferredSize()
    }

    private func applyProcessesCollapsedState() {
        let collapsed = Settings.shared.processesCollapsed
        processListStack.isHidden = collapsed
        // moreButton 的可見度同時受 collapsed 跟「是否有 extra」影響
        let hasExtras = allProcesses.count > Settings.shared.topProcessCount
        moreProcessesButton.isHidden = collapsed || !hasExtras
        processesHeaderButton.title = collapsed ? "▶  TOP PROCESSES" : "▼  TOP PROCESSES"
        processesHeaderButton.setAccessibilityValue(collapsed ? "Collapsed" : "Expanded")
    }

    @objc private func toggleProcessesCollapsed() {
        Settings.shared.processesCollapsed.toggle()
        // settingsChanged 通知會回頭呼叫 applyProcessSettings()，這裡不用再做事
    }

    // MARK: - Process list

    private func rebuildProcessRows() {
        let target = Settings.shared.topProcessCount
        while processRows.count > target {
            let removed = processRows.removeLast()
            processListStack.removeArrangedSubview(removed)
            removed.removeFromSuperview()
        }
        while processRows.count < target {
            let row = ProcessRowControl()
            row.translatesAutoresizingMaskIntoConstraints = false
            row.onClick = { [weak self] entry, anchor in
                self?.showActionMenu(for: entry, anchor: anchor)
            }
            processListStack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: processListStack.widthAnchor).isActive = true
            processRows.append(row)
        }
        updateProcessRowContents()
    }

    func updateProcesses(_ entries: [ProcessMonitor.Entry]) {
        allProcesses = entries
        updateProcessRowContents()
        adjustPreferredSize()
    }

    private func updateProcessRowContents() {
        for (idx, row) in processRows.enumerated() {
            row.update(idx < allProcesses.count ? allProcesses[idx] : nil)
        }
        // moreButton 的最終可見度由 applyProcessesCollapsedState 統一處理，
        // 避免 collapsed 狀態被資料更新覆蓋掉。
        applyProcessesCollapsedState()
    }

    @objc private func showMoreProcessesMenu(_ sender: NSButton) {
        let visible = Settings.shared.topProcessCount
        let extras = Array(allProcesses.dropFirst(visible))
        let menu = NSMenu()
        if extras.isEmpty {
            let empty = NSMenuItem(title: "No additional processes", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        } else {
            for entry in extras {
                let title = String(format: "%@   %.1f%%", entry.name, entry.cpuPercent)
                let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
                item.submenu = buildActionMenu(for: entry)
                menu.addItem(item)
            }
        }
        menu.popUp(positioning: nil,
                   at: NSPoint(x: 0, y: sender.bounds.height + 2),
                   in: sender)
    }

    private func showActionMenu(for entry: ProcessMonitor.Entry, anchor: NSView) {
        let menu = buildActionMenu(for: entry, includeHeader: true)
        menu.popUp(positioning: nil,
                   at: NSPoint(x: anchor.bounds.midX, y: anchor.bounds.height),
                   in: anchor)
    }

    private func buildActionMenu(for entry: ProcessMonitor.Entry, includeHeader: Bool = false) -> NSMenu {
        let menu = NSMenu()
        if includeHeader {
            let header = NSMenuItem(title: "\(entry.name) — PID \(entry.pid)", action: nil, keyEquivalent: "")
            header.isEnabled = false
            menu.addItem(header)
            menu.addItem(.separator())
        }

        let quit = NSMenuItem(title: "Quit", action: #selector(menuQuitProcess(_:)), keyEquivalent: "")
        quit.target = self
        quit.representedObject = entry
        menu.addItem(quit)

        let force = NSMenuItem(title: "Force Kill", action: #selector(menuForceKillProcess(_:)), keyEquivalent: "")
        force.target = self
        force.representedObject = entry
        menu.addItem(force)

        menu.addItem(.separator())

        let copy = NSMenuItem(title: "Copy PID (\(entry.pid))", action: #selector(menuCopyPID(_:)), keyEquivalent: "")
        copy.target = self
        copy.representedObject = entry
        menu.addItem(copy)

        return menu
    }

    @objc private func menuQuitProcess(_ sender: NSMenuItem) {
        guard let entry = sender.representedObject as? ProcessMonitor.Entry else { return }
        confirmAndPerform(entry: entry, action: .quit)
    }

    @objc private func menuForceKillProcess(_ sender: NSMenuItem) {
        guard let entry = sender.representedObject as? ProcessMonitor.Entry else { return }
        confirmAndPerform(entry: entry, action: .forceKill)
    }

    @objc private func menuCopyPID(_ sender: NSMenuItem) {
        guard let entry = sender.representedObject as? ProcessMonitor.Entry else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(String(entry.pid), forType: .string)
    }

    private func confirmAndPerform(entry: ProcessMonitor.Entry, action: ProcessAction) {
        let alert = NSAlert()
        switch action {
        case .quit:
            alert.messageText = "Quit “\(entry.name)”?"
            alert.informativeText = "Sends SIGTERM to PID \(entry.pid). The app will be asked to quit normally."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Quit")
        case .forceKill:
            alert.messageText = "Force kill “\(entry.name)”?"
            alert.informativeText = "Sends SIGKILL to PID \(entry.pid). Any unsaved work in this process will be lost."
            alert.alertStyle = .critical
            alert.addButton(withTitle: "Force Kill")
        }
        alert.addButton(withTitle: "Cancel")

        // NSAlert sheet modal 是非同步的；popover 上跑 sheet 不漂亮，
        // 直接 runModal 把 alert 拉到最前面即可。
        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return }
        processActionHandler?(entry, action)
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
        emptyStateView.isHidden = !visible.isEmpty
        emptyStateDivider.isHidden = !visible.isEmpty
        adjustPreferredSize()
    }

    private func adjustPreferredSize() {
        rootStack.layoutSubtreeIfNeeded()
        let contentHeight = max(rootStack.fittingSize.height, 80)
        let cappedHeight = min(contentHeight, maximumPopoverHeight())
        scrollView.hasVerticalScroller = contentHeight > cappedHeight + 1
        preferredContentSize = NSSize(width: 280, height: cappedHeight)
    }

    func prepareForDisplay(on screen: NSScreen?) {
        preferredScreen = screen
        adjustPreferredSize()
    }

    private func maximumPopoverHeight() -> CGFloat {
        let screen = view.window?.screen ?? preferredScreen ?? NSScreen.main
        let visibleHeight = screen?.visibleFrame.height ?? 600
        return max(180, visibleHeight - 80)
    }

    // MARK: - Sample updates

    /// Cheap path: only feeds sparkline buffers so opening the popover later
    /// shows fresh history. Called every tick regardless of popover visibility.
    func appendSamples(cpu: CPUMonitor.Sample?,
                       gpu: GPUMonitor.Sample?,
                       memory: MemoryMonitor.Sample?,
                       network: NetworkMonitor.Sample?) {
        if let cpu     { cpuSparkline.append(cpu.total) }
        if let gpu, let utilization = gpu.utilizationPercent { gpuSparkline.append(utilization) }
        if let memory  { memSparkline.append(memory.usagePercent) }
        if let network { netSparkline.append(network.downloadBytesPerSec + network.uploadBytesPerSec) }
    }

    func update(cpu: CPUMonitor.Sample?,
                gpu: GPUMonitor.Sample?,
                memory: MemoryMonitor.Sample?,
                network: NetworkMonitor.Sample?,
                disk: DiskMonitor.Sample?,
                temperature: TemperatureMonitor.Sample?,
                power: PowerMonitor.Sample?) {

        if let cpu {
            cpuValueLabel.stringValue = String(format: "%.1f %%", cpu.total)
            cpuBreakdown.stringValue = String(format: "user %.1f · system %.1f · idle %.1f",
                                              cpu.user, cpu.system, cpu.idle)
        }

        if let gpu {
            if let utilization = gpu.utilizationPercent {
                gpuValueLabel.stringValue = String(format: "%.1f %%", utilization)
            } else {
                gpuValueLabel.stringValue = "—"
            }

            var parts: [String] = []
            if let renderer = gpu.rendererPercent {
                parts.append(String(format: "renderer %.0f %%", renderer))
            }
            if let tiler = gpu.tilerPercent {
                parts.append(String(format: "tiler %.0f %%", tiler))
            }
            if let memory = gpu.usedMemoryBytes {
                parts.append("mem \(ByteFormatter.size(memory))")
            }
            if parts.isEmpty, let model = gpu.modelName {
                if let cores = gpu.coreCount {
                    parts.append("\(model) · \(cores) cores")
                } else {
                    parts.append(model)
                }
            }
            gpuBreakdown.stringValue = parts.isEmpty ? "no GPU stats" : parts.joined(separator: " · ")
        }

        if let memory {
            memValueLabel.stringValue = String(format: "%.1f %%", memory.usagePercent)
            memBreakdown.stringValue = "\(ByteFormatter.size(memory.usedBytes)) / \(ByteFormatter.size(memory.totalBytes))"
        }

        if let network {
            downLabel.stringValue = ByteFormatter.rate(network.downloadBytesPerSec)
            upLabel.stringValue   = ByteFormatter.rate(network.uploadBytesPerSec)
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

        if let power {
            switch power.state {
            case .charging:
                powerLabel.stringValue = String(format: "↑ %.1f W", power.watts ?? 0)
                powerBreakdown.stringValue = "charging" + (power.percent.map { " · \($0)%" } ?? "")
            case .discharging:
                powerLabel.stringValue = String(format: "↓ %.1f W", power.watts ?? 0)
                powerBreakdown.stringValue = "on battery" + (power.percent.map { " · \($0)%" } ?? "")
            case .ac:
                powerLabel.stringValue = "AC"
                powerBreakdown.stringValue = "plugged in" + (power.percent.map { " · \($0)%" } ?? "")
            case .unavailable:
                powerLabel.stringValue = "—"
                powerBreakdown.stringValue = "no battery"
            }
        }
    }

    // MARK: - Action plumbing

    @objc private func openSettings() { onOpenSettings?() }
    @objc private func quitApp()      { onQuit?() }

    // MARK: - View helpers

    private func headerRow(metric: Metric, valueView: NSView?) -> NSStackView {
        let icon = NSImageView()
        if let img = NSImage(systemSymbolName: metric.symbolName, accessibilityDescription: metric.displayName) {
            icon.image = img.withSymbolConfiguration(.init(pointSize: 13, weight: .medium))
        }
        icon.contentTintColor = .secondaryLabelColor
        icon.toolTip = metric.displayName
        icon.setAccessibilityLabel("\(metric.displayName) icon")
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.widthAnchor.constraint(equalToConstant: 18).isActive = true

        let title = NSTextField(labelWithString: metric.displayName.uppercased())
        title.font = NSFont.systemFont(ofSize: 10, weight: .semibold)
        title.textColor = .secondaryLabelColor
        title.setAccessibilityLabel(metric.displayName)

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
        switch symbol {
        case "↓":
            symbolLabel.toolTip = "Download"
            symbolLabel.setAccessibilityLabel("Download rate")
            value.setAccessibilityLabel("Download rate")
        case "↑":
            symbolLabel.toolTip = "Upload"
            symbolLabel.setAccessibilityLabel("Upload rate")
            value.setAccessibilityLabel("Upload rate")
        case "R":
            symbolLabel.toolTip = "Disk read"
            symbolLabel.setAccessibilityLabel("Disk read rate")
            value.setAccessibilityLabel("Disk read rate")
        case "W":
            symbolLabel.toolTip = "Disk write"
            symbolLabel.setAccessibilityLabel("Disk write rate")
            value.setAccessibilityLabel("Disk write rate")
        default:
            break
        }

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

    private func iconButton(symbol: String, accessibilityLabel: String, action: Selector) -> NSButton {
        let button = NSButton()
        button.bezelStyle = .accessoryBarAction
        button.isBordered = false
        if let img = NSImage(systemSymbolName: symbol, accessibilityDescription: accessibilityLabel) {
            button.image = img.withSymbolConfiguration(.init(pointSize: 13, weight: .medium))
        }
        button.target = self
        button.action = action
        button.contentTintColor = .secondaryLabelColor
        button.setAccessibilityLabel(accessibilityLabel)
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

/// 行程列表中的一列：左側顯示名稱，右側顯示 CPU%，整行可點擊彈出選單。
final class ProcessRowControl: NSControl {
    private let nameLabel = NSTextField(labelWithString: "")
    private let cpuLabel = NSTextField(labelWithString: "")
    private let chevron = NSImageView()
    private var trackingArea: NSTrackingArea?
    private var entry: ProcessMonitor.Entry?

    /// 點擊時 callback：傳回該行 entry 與 anchor view（讓呼叫端決定要怎麼定位選單）。
    var onClick: ((ProcessMonitor.Entry, NSView) -> Void)?

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 4
        setAccessibilityElement(true)
        setAccessibilityLabel("Process")
        setAccessibilityHelp("Open process actions")

        nameLabel.font = NSFont.systemFont(ofSize: 12, weight: .regular)
        nameLabel.textColor = .labelColor
        nameLabel.lineBreakMode = .byTruncatingMiddle
        nameLabel.cell?.usesSingleLineMode = true
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        nameLabel.setContentCompressionResistancePriority(.defaultLow - 1, for: .horizontal)
        nameLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)

        cpuLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        cpuLabel.textColor = .secondaryLabelColor
        cpuLabel.alignment = .right
        cpuLabel.translatesAutoresizingMaskIntoConstraints = false
        cpuLabel.setContentHuggingPriority(.required, for: .horizontal)
        cpuLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        if let img = NSImage(systemSymbolName: "chevron.right", accessibilityDescription: nil) {
            chevron.image = img.withSymbolConfiguration(.init(pointSize: 9, weight: .semibold))
        }
        chevron.contentTintColor = .tertiaryLabelColor
        chevron.translatesAutoresizingMaskIntoConstraints = false

        addSubview(nameLabel)
        addSubview(cpuLabel)
        addSubview(chevron)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 20),

            nameLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            nameLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            cpuLabel.leadingAnchor.constraint(greaterThanOrEqualTo: nameLabel.trailingAnchor, constant: 8),
            cpuLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            cpuLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 44),

            chevron.leadingAnchor.constraint(equalTo: cpuLabel.trailingAnchor, constant: 4),
            chevron.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            chevron.centerYAnchor.constraint(equalTo: centerYAnchor),
            chevron.widthAnchor.constraint(equalToConstant: 10)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        guard entry != nil else { return }
        layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.18).cgColor
    }

    override func mouseExited(with event: NSEvent) {
        layer?.backgroundColor = nil
    }

    override func mouseDown(with event: NSEvent) {
        guard let entry else { return }
        onClick?(entry, self)
    }

    override var acceptsFirstResponder: Bool { false }

    func update(_ entry: ProcessMonitor.Entry?) {
        self.entry = entry
        if let entry {
            nameLabel.stringValue = entry.name
            cpuLabel.stringValue = String(format: "%.1f%%", entry.cpuPercent)
            chevron.isHidden = false
            isHidden = false
            toolTip = String(format: "%@\nPID %d\nCPU %.1f%%",
                             entry.command,
                             entry.pid,
                             entry.cpuPercent)
            setAccessibilityLabel("\(entry.name), PID \(entry.pid)")
            setAccessibilityValue(String(format: "%.1f percent CPU", entry.cpuPercent))
            setAccessibilityHelp("Open actions for \(entry.name)")
        } else {
            nameLabel.stringValue = "—"
            cpuLabel.stringValue = ""
            chevron.isHidden = true
            isHidden = true
            toolTip = nil
            setAccessibilityLabel("Process")
            setAccessibilityValue(nil)
            setAccessibilityHelp("No process")
        }
    }
}

private final class FlippedDocumentView: NSView {
    override var isFlipped: Bool { true }
}
