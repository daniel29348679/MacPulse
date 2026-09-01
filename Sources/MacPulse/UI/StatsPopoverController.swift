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
    private let overviewPageController = NSViewController()
    private var navigationContainer: NSView?
    private var processNavigation = ProcessNavigationState()
    private var processPageControllers: [NSViewController] = []
    private var processPageReturnFocusViews: [NSView?] = []
    private var isProcessTransitioning = false
    private var pendingProcessNavigationReset = false
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
    private var emptyStateCard: NSView?
    private var statusPairRow: NSStackView?

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
        let button = NSButton(title: "Top Processes", target: nil, action: nil)
        button.bezelStyle = .accessoryBarAction
        button.isBordered = false
        button.alignment = .left
        button.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        button.contentTintColor = .secondaryLabelColor
        button.imagePosition = .imageLeading
        button.imageHugsTitle = true
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
        let button = NSButton(title: "View Processes", target: nil, action: nil)
        button.bezelStyle = .accessoryBarAction
        button.isBordered = false
        button.contentTintColor = .controlAccentColor
        button.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        if let image = NSImage(systemSymbolName: "chevron.right", accessibilityDescription: nil) {
            button.image = image.withSymbolConfiguration(.init(pointSize: 9, weight: .semibold))
        }
        button.imagePosition = .imageTrailing
        button.imageHugsTitle = true
        button.toolTip = "Browse CPU processes"
        button.setAccessibilityLabel("Browse CPU processes")
        return button
    }()
    private var processRows: [ProcessRowControl] = []
    private var allGroups: [ProcessMonitor.Group] = []
    /// 由外部（StatusBarController）注入：執行 Quit / Force Kill 並回報結果。
    /// 群組只是顯示層的彙總 — 操作永遠針對個別 Entry。
    var processActionHandler: ((ProcessMonitor.Entry, ProcessAction) -> Void)?

    enum ProcessAction {
        case quit       // SIGTERM
        case forceKill  // SIGKILL
    }

    // Memory
    private let memValueLabel = StatsPopoverController.makeValueLabel()
    private let memBreakdown = StatsPopoverController.makeSecondaryLabel()
    private let swapUsedLabel = StatsPopoverController.makeSecondaryLabel()
    private let memSparkline = SparklineView(capacity: 60)

    // Top memory processes (within the Memory section)
    private let memoryProcessesHeaderButton: NSButton = {
        let button = NSButton(title: "Top Memory Processes", target: nil, action: nil)
        button.bezelStyle = .accessoryBarAction
        button.isBordered = false
        button.alignment = .left
        button.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        button.contentTintColor = .secondaryLabelColor
        button.imagePosition = .imageLeading
        button.imageHugsTitle = true
        button.toolTip = "Click to collapse / expand"
        button.setAccessibilityLabel("Top memory processes")
        button.setAccessibilityHelp("Collapse or expand the top memory processes list.")
        return button
    }()
    private let memoryProcessListStack: NSStackView = {
        let s = NSStackView()
        s.orientation = .vertical
        s.alignment = .leading
        s.spacing = 1
        return s
    }()
    private let moreMemoryProcessesButton: NSButton = {
        let button = NSButton(title: "View Processes", target: nil, action: nil)
        button.bezelStyle = .accessoryBarAction
        button.isBordered = false
        button.contentTintColor = .controlAccentColor
        button.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        if let image = NSImage(systemSymbolName: "chevron.right", accessibilityDescription: nil) {
            button.image = image.withSymbolConfiguration(.init(pointSize: 9, weight: .semibold))
        }
        button.imagePosition = .imageTrailing
        button.imageHugsTitle = true
        button.toolTip = "Browse memory processes"
        button.setAccessibilityLabel("Browse memory processes")
        return button
    }()
    private var memoryProcessRows: [ProcessRowControl] = []
    private var allMemoryGroups: [ProcessMonitor.Group] = []

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
        label.font = NSFont.monospacedDigitSystemFont(ofSize: 10.5, weight: .medium)
        label.textColor = .tertiaryLabelColor
        return label
    }()

    var onOpenSettings: (() -> Void)?
    var onQuit: (() -> Void)?

    private lazy var rootStack: NSStackView = NSStackView()

    override func loadView() {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false

        // Brand and top-level actions. NSPopover provides the main glass surface;
        // only the controls sit in the elevated Liquid Glass layer.
        let brandIcon = MacPulseVisualStyle.symbolBadge(
            "waveform.path.ecg",
            color: .controlAccentColor,
            accessibilityDescription: "MacPulse",
            size: 32
        )
        let title = NSTextField(labelWithString: "MacPulse")
        title.font = NSFont.systemFont(ofSize: 17, weight: .semibold)
        title.textColor = .labelColor

        let subtitle = NSTextField(labelWithString: "Live system overview")
        subtitle.font = NSFont.systemFont(ofSize: 10.5, weight: .medium)
        subtitle.textColor = .secondaryLabelColor

        let titleStack = stack([title, subtitle], spacing: 1)
        let settingsButton = iconButton(symbol: "gearshape",
                                        accessibilityLabel: "Open Settings",
                                        action: #selector(openSettings))
        settingsButton.toolTip = "Settings"
        let quitButton = iconButton(symbol: "power",
                                    accessibilityLabel: "Quit MacPulse",
                                    action: #selector(quitApp))
        quitButton.toolTip = "Quit MacPulse"
        quitButton.hasDestructiveAction = true

        let actions = NSStackView(views: [settingsButton, quitButton])
        actions.orientation = .horizontal
        actions.alignment = .centerY
        actions.spacing = 6

        let header = NSStackView(views: [brandIcon, titleStack, NSView(), actions])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 9

        // CPU section
        cpuSparkline.fixedMaxValue = 100
        cpuSparkline.lineColor = .systemBlue
        cpuSparkline.fillColor = NSColor.systemBlue.withAlphaComponent(0.16)
        cpuSparkline.heightAnchor.constraint(equalToConstant: 32).isActive = true

        let cpuRow = headerRow(metric: .cpu, valueView: cpuValueLabel)

        moreProcessesButton.target = self
        moreProcessesButton.action = #selector(showCPUProcessesPage(_:))
        processesHeaderButton.target = self
        processesHeaderButton.action = #selector(toggleProcessesCollapsed)

        let processesSection = stack([processesHeaderButton, processListStack, moreProcessesButton], spacing: 4)

        let cpuSection = stack([cpuRow, cpuBreakdown, cpuSparkline, processesSection], spacing: 7)
        sections[.cpu] = popoverCard(around: cpuSection)

        // Process list 寬度跟著 CPU section 撐滿
        processListStack.translatesAutoresizingMaskIntoConstraints = false
        processListStack.widthAnchor.constraint(equalTo: processesSection.widthAnchor).isActive = true
        processesSection.translatesAutoresizingMaskIntoConstraints = false
        processesSection.widthAnchor.constraint(equalTo: cpuSection.widthAnchor).isActive = true
        processesHeaderButton.translatesAutoresizingMaskIntoConstraints = false
        processesHeaderButton.widthAnchor.constraint(equalTo: processesSection.widthAnchor).isActive = true
        cpuRow.translatesAutoresizingMaskIntoConstraints = false
        cpuRow.widthAnchor.constraint(equalTo: cpuSection.widthAnchor).isActive = true
        cpuSparkline.translatesAutoresizingMaskIntoConstraints = false
        cpuSparkline.widthAnchor.constraint(equalTo: cpuSection.widthAnchor).isActive = true

        rebuildProcessRows()
        applyProcessesCollapsedState()

        // GPU
        gpuSparkline.fixedMaxValue = 100
        gpuSparkline.lineColor = .systemTeal
        gpuSparkline.fillColor = NSColor.systemTeal.withAlphaComponent(0.16)
        gpuSparkline.heightAnchor.constraint(equalToConstant: 32).isActive = true

        let gpuRow = headerRow(metric: .gpu, valueView: gpuValueLabel)
        let gpuSection = stack([gpuRow, gpuBreakdown, gpuSparkline], spacing: 7)
        gpuRow.widthAnchor.constraint(equalTo: gpuSection.widthAnchor).isActive = true
        gpuSparkline.widthAnchor.constraint(equalTo: gpuSection.widthAnchor).isActive = true
        sections[.gpu] = popoverCard(around: gpuSection)

        // Memory
        memSparkline.fixedMaxValue = 100
        memSparkline.lineColor = .systemPurple
        memSparkline.fillColor = NSColor.systemPurple.withAlphaComponent(0.16)
        memSparkline.heightAnchor.constraint(equalToConstant: 32).isActive = true

        let memRow = headerRow(metric: .memory, valueView: memValueLabel)
        let memDetails = NSStackView(views: [memBreakdown, NSView(), swapUsedLabel])
        memDetails.orientation = .horizontal
        memDetails.alignment = .firstBaseline
        memDetails.spacing = 8

        moreMemoryProcessesButton.target = self
        moreMemoryProcessesButton.action = #selector(showMemoryProcessesPage(_:))
        memoryProcessesHeaderButton.target = self
        memoryProcessesHeaderButton.action = #selector(toggleMemoryProcessesCollapsed)

        let memoryProcessesSection = stack(
            [memoryProcessesHeaderButton, memoryProcessListStack, moreMemoryProcessesButton],
            spacing: 4
        )
        let memSection = stack([memRow, memDetails, memSparkline, memoryProcessesSection], spacing: 7)
        memDetails.translatesAutoresizingMaskIntoConstraints = false
        memDetails.widthAnchor.constraint(equalTo: memSection.widthAnchor).isActive = true
        memRow.widthAnchor.constraint(equalTo: memSection.widthAnchor).isActive = true
        memSparkline.widthAnchor.constraint(equalTo: memSection.widthAnchor).isActive = true
        sections[.memory] = popoverCard(around: memSection)

        memoryProcessListStack.translatesAutoresizingMaskIntoConstraints = false
        memoryProcessListStack.widthAnchor.constraint(equalTo: memoryProcessesSection.widthAnchor).isActive = true
        memoryProcessesSection.translatesAutoresizingMaskIntoConstraints = false
        memoryProcessesSection.widthAnchor.constraint(equalTo: memSection.widthAnchor).isActive = true
        memoryProcessesHeaderButton.translatesAutoresizingMaskIntoConstraints = false
        memoryProcessesHeaderButton.widthAnchor.constraint(equalTo: memoryProcessesSection.widthAnchor).isActive = true

        rebuildMemoryProcessRows()
        applyMemoryProcessesCollapsedState()

        // Network
        netSparkline.lineColor = .systemGreen
        netSparkline.fillColor = NSColor.systemGreen.withAlphaComponent(0.16)
        netSparkline.heightAnchor.constraint(equalToConstant: 32).isActive = true

        let downRow = labelledRow(symbol: "↓", value: downLabel)
        let upRow = labelledRow(symbol: "↑", value: upLabel)
        let netHeader = headerRow(metric: .network, valueView: nil)
        let netRates = NSStackView(views: [downRow, upRow])
        netRates.orientation = .horizontal
        netRates.distribution = .fillEqually
        netRates.spacing = 10
        let netSection = stack([netHeader, netRates, netSparkline], spacing: 8)
        netHeader.widthAnchor.constraint(equalTo: netSection.widthAnchor).isActive = true
        netRates.widthAnchor.constraint(equalTo: netSection.widthAnchor).isActive = true
        netSparkline.widthAnchor.constraint(equalTo: netSection.widthAnchor).isActive = true
        sections[.network] = popoverCard(around: netSection)

        // Disk
        let readRow = labelledRow(symbol: "R", value: diskReadLabel)
        let writeRow = labelledRow(symbol: "W", value: diskWriteLabel)
        let diskHeader = headerRow(metric: .disk, valueView: nil)
        let diskRates = NSStackView(views: [readRow, writeRow])
        diskRates.orientation = .horizontal
        diskRates.distribution = .fillEqually
        diskRates.spacing = 10
        let diskSection = stack([diskHeader, diskRates], spacing: 9)
        diskHeader.widthAnchor.constraint(equalTo: diskSection.widthAnchor).isActive = true
        diskRates.widthAnchor.constraint(equalTo: diskSection.widthAnchor).isActive = true
        sections[.disk] = popoverCard(around: diskSection)

        // Temperature
        tempDot.translatesAutoresizingMaskIntoConstraints = false
        tempDot.widthAnchor.constraint(equalToConstant: 8).isActive = true
        tempDot.heightAnchor.constraint(equalToConstant: 8).isActive = true

        let tempValueRow = NSStackView(views: [tempLabel, tempDot])
        tempValueRow.orientation = .horizontal
        tempValueRow.spacing = 6
        tempValueRow.alignment = .centerY

        let tempHeader = compactHeaderRow(metric: .temperature)
        let tempSection = stack([tempHeader, tempValueRow, tempBreakdown], spacing: 5)
        tempHeader.widthAnchor.constraint(equalTo: tempSection.widthAnchor).isActive = true
        let tempCard = popoverCard(around: tempSection)
        sections[.temperature] = tempCard

        // Power
        let powerHeader = compactHeaderRow(metric: .power)
        let powerSection = stack([powerHeader, powerLabel, powerBreakdown], spacing: 5)
        powerHeader.widthAnchor.constraint(equalTo: powerSection.widthAnchor).isActive = true
        let powerCard = popoverCard(around: powerSection)
        sections[.power] = powerCard

        let statusPair = NSStackView(views: [tempCard, powerCard])
        statusPair.orientation = .horizontal
        statusPair.alignment = .top
        statusPair.distribution = .fillEqually
        statusPair.spacing = 8
        statusPairRow = statusPair

        // Compose the content layer as semantic material cards. Glass remains
        // reserved for the popover surface and top-level action buttons.
        var rootSubviews: [NSView] = [header]
        for metric in Metric.allCases where metric != .temperature && metric != .power {
            if let section = sections[metric] {
                rootSubviews.append(section)
            }
        }
        rootSubviews.append(statusPair)

        let emptyCard = popoverCard(around: emptyStateView)
        emptyStateCard = emptyCard
        rootSubviews.append(emptyCard)

        let liveDot = ColorDotView()
        liveDot.color = .systemGreen
        liveDot.translatesAutoresizingMaskIntoConstraints = false
        liveDot.widthAnchor.constraint(equalToConstant: 7).isActive = true
        liveDot.heightAnchor.constraint(equalToConstant: 7).isActive = true
        let liveLabel = NSTextField(labelWithString: "Live")
        liveLabel.font = NSFont.systemFont(ofSize: 10.5, weight: .medium)
        liveLabel.textColor = .secondaryLabelColor
        let footerRow = NSStackView(views: [liveDot, liveLabel, NSView(), versionLabel])
        footerRow.orientation = .horizontal
        footerRow.alignment = .centerY
        footerRow.spacing = 5
        rootSubviews.append(footerRow)

        rootStack = NSStackView(views: rootSubviews)
        rootStack.orientation = .vertical
        rootStack.alignment = .leading
        rootStack.spacing = 8
        rootStack.edgeInsets = NSEdgeInsets(top: 12, left: 12, bottom: 10, right: 12)
        rootStack.translatesAutoresizingMaskIntoConstraints = false

        scrollDocumentView.translatesAutoresizingMaskIntoConstraints = false
        scrollDocumentView.addSubview(rootStack)
        scrollView.documentView = scrollDocumentView
        scrollView.translatesAutoresizingMaskIntoConstraints = true
        scrollView.frame = container.bounds
        scrollView.autoresizingMask = [.width, .height]
        overviewPageController.view = scrollView
        addChild(overviewPageController)
        container.wantsLayer = true
        container.layer?.masksToBounds = true
        container.addSubview(scrollView)
        navigationContainer = container
        NSLayoutConstraint.activate([
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
            view.widthAnchor.constraint(equalTo: rootStack.widthAnchor, constant: -24).isActive = true
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
        rebuildMemoryProcessRows()
        applyProcessesCollapsedState()
        applyMemoryProcessesCollapsedState()
        adjustPreferredSize()
    }

    private func applyProcessesCollapsedState() {
        let collapsed = Settings.shared.processesCollapsed
        processListStack.isHidden = collapsed
        // moreButton 的可見度同時受 collapsed 跟「是否有 extra」影響
        let hasExtras = allGroups.count > Settings.shared.topProcessCount
        moreProcessesButton.isHidden = collapsed || !hasExtras
        processesHeaderButton.image = NSImage(
            systemSymbolName: collapsed ? "chevron.right" : "chevron.down",
            accessibilityDescription: nil
        )?.withSymbolConfiguration(.init(pointSize: 9, weight: .semibold))
        processesHeaderButton.setAccessibilityValue(collapsed ? "Collapsed" : "Expanded")
    }

    @objc private func toggleProcessesCollapsed() {
        Settings.shared.processesCollapsed.toggle()
        applyProcessesCollapsedState()
        adjustPreferredSize()
    }

    private func applyMemoryProcessesCollapsedState() {
        let collapsed = Settings.shared.memoryProcessesCollapsed
        memoryProcessListStack.isHidden = collapsed
        let hasExtras = allMemoryGroups.count > Settings.shared.topProcessCount
        moreMemoryProcessesButton.isHidden = collapsed || !hasExtras
        memoryProcessesHeaderButton.image = NSImage(
            systemSymbolName: collapsed ? "chevron.right" : "chevron.down",
            accessibilityDescription: nil
        )?.withSymbolConfiguration(.init(pointSize: 9, weight: .semibold))
        memoryProcessesHeaderButton.setAccessibilityValue(collapsed ? "Collapsed" : "Expanded")
    }

    @objc private func toggleMemoryProcessesCollapsed() {
        Settings.shared.memoryProcessesCollapsed.toggle()
        applyMemoryProcessesCollapsedState()
        adjustPreferredSize()
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
            row.onClick = { [weak self] group, anchor in
                self?.showProcessGroupOrEntry(group, resource: .cpu, returnFocusTo: anchor)
            }
            processListStack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: processListStack.widthAnchor).isActive = true
            processRows.append(row)
        }
        updateProcessRowContents()
    }

    private func rebuildMemoryProcessRows() {
        let target = Settings.shared.topProcessCount
        while memoryProcessRows.count > target {
            let removed = memoryProcessRows.removeLast()
            memoryProcessListStack.removeArrangedSubview(removed)
            removed.removeFromSuperview()
        }
        while memoryProcessRows.count < target {
            let row = ProcessRowControl(resource: .memory)
            row.translatesAutoresizingMaskIntoConstraints = false
            row.onClick = { [weak self] group, anchor in
                self?.showProcessGroupOrEntry(group, resource: .memory, returnFocusTo: anchor)
            }
            memoryProcessListStack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: memoryProcessListStack.widthAnchor).isActive = true
            memoryProcessRows.append(row)
        }
        updateMemoryProcessRowContents()
    }

    func updateProcesses(_ groups: [ProcessMonitor.Group]) {
        let topCount = Settings.shared.topProcessCount
        let rowsBefore = min(allGroups.count, processRows.count)
        let extrasBefore = allGroups.count > topCount
        allGroups = groups
        updateProcessRowContents()
        updateVisibleProcessPage(for: .cpu)
        // 列高固定 — 只有可見列數或 More 按鈕的顯示狀態改變時才需要
        // 重新 layout；每秒對整棵 view tree 跑 layoutSubtreeIfNeeded 太浪費。
        let rowsAfter = min(allGroups.count, processRows.count)
        let extrasAfter = allGroups.count > topCount
        if rowsBefore != rowsAfter || extrasBefore != extrasAfter {
            adjustPreferredSize(preservingVisibleSize: true)
        }
    }

    func updateMemoryProcesses(_ groups: [ProcessMonitor.Group]) {
        let topCount = Settings.shared.topProcessCount
        let rowsBefore = min(allMemoryGroups.count, memoryProcessRows.count)
        let extrasBefore = allMemoryGroups.count > topCount
        allMemoryGroups = groups
        updateMemoryProcessRowContents()
        updateVisibleProcessPage(for: .memory)
        let rowsAfter = min(allMemoryGroups.count, memoryProcessRows.count)
        let extrasAfter = allMemoryGroups.count > topCount
        if rowsBefore != rowsAfter || extrasBefore != extrasAfter {
            adjustPreferredSize(preservingVisibleSize: true)
        }
    }

    private func updateProcessRowContents() {
        for (idx, row) in processRows.enumerated() {
            row.update(idx < allGroups.count ? allGroups[idx] : nil)
        }
        // moreButton 的最終可見度由 applyProcessesCollapsedState 統一處理，
        // 避免 collapsed 狀態被資料更新覆蓋掉。
        applyProcessesCollapsedState()
    }

    private func updateMemoryProcessRowContents() {
        for (idx, row) in memoryProcessRows.enumerated() {
            row.update(idx < allMemoryGroups.count ? allMemoryGroups[idx] : nil)
        }
        applyMemoryProcessesCollapsedState()
    }

    @objc private func showCPUProcessesPage(_ sender: NSButton) {
        pushProcessPage(.list(.cpu), returnFocusTo: sender)
    }

    @objc private func showMemoryProcessesPage(_ sender: NSButton) {
        pushProcessPage(.list(.memory), returnFocusTo: sender)
    }

    private func showProcessGroupOrEntry(_ group: ProcessMonitor.Group,
                                         resource: ProcessMonitor.Resource,
                                         returnFocusTo view: NSView) {
        if group.entries.count == 1, let entry = group.entries.first {
            showProcessEntry(entry,
                             groupName: group.name,
                             resource: resource,
                             returnFocusTo: view)
        } else {
            pushProcessPage(.group(resource, name: group.name),
                            returnFocusTo: view)
        }
    }

    private func showProcessEntry(_ entry: ProcessMonitor.Entry,
                                  groupName: String,
                                  resource: ProcessMonitor.Resource,
                                  returnFocusTo view: NSView) {
        pushProcessPage(
            .entry(resource, groupName: groupName, id: ProcessEntryID(entry)),
            fallbackEntry: entry,
            returnFocusTo: view
        )
    }

    private func pushProcessPage(_ route: ProcessNavigationState.Route,
                                 fallbackEntry: ProcessMonitor.Entry? = nil,
                                 returnFocusTo view: NSView) {
        guard !isProcessTransitioning,
              let destination = makeProcessPageController(route: route,
                                                          fallbackEntry: fallbackEntry),
              processNavigation.push(route) else { return }

        let source = processPageControllers.last ?? overviewPageController
        destination.view.frame = source.view.frame
        destination.view.autoresizingMask = [.width, .height]
        addChild(destination)
        processPageControllers.append(destination)
        processPageReturnFocusViews.append(view)
        let options = processTransitionOptions(forward: true)
        let completion = { [weak self, weak destination] in
            guard let self else { return }
            self.isProcessTransitioning = false
            if self.pendingProcessNavigationReset {
                self.resetProcessNavigation()
                self.adjustPreferredSize()
                return
            }
            if let destination {
                self.focusProcessPage(destination)
            }
        }
        if options.isEmpty {
            let parent = source.view.superview ?? navigationContainer
            source.view.removeFromSuperview()
            parent?.addSubview(destination.view)
            completion()
        } else {
            isProcessTransitioning = true
            transition(from: source,
                       to: destination,
                       options: options,
                       completionHandler: completion)
        }
    }

    private func makeProcessPageController(route: ProcessNavigationState.Route,
                                           fallbackEntry: ProcessMonitor.Entry?) -> NSViewController? {
        let groups = groups(for: route.resource)
        let page: ProcessPageView

        switch route {
        case .list(let resource):
            let list = ProcessListPageView(resource: resource, groups: groups)
            list.onSelectGroup = { [weak self] group, anchor in
                self?.showProcessGroupOrEntry(group,
                                              resource: resource,
                                              returnFocusTo: anchor)
            }
            page = list

        case .group(let resource, let name):
            let group = ProcessGroupPageView(resource: resource,
                                             groupName: name,
                                             groups: groups)
            group.onSelectEntry = { [weak self] entry, anchor in
                self?.showProcessEntry(entry,
                                       groupName: name,
                                       resource: resource,
                                       returnFocusTo: anchor)
            }
            page = group

        case .entry(let resource, let groupName, let id):
            let resolved = id.resolve(in: groups, groupName: groupName)
            guard let entry = resolved ?? fallbackEntry else { return nil }
            let detail = ProcessEntryPageView(resource: resource,
                                              groupName: groupName,
                                              entry: entry,
                                              groups: groups)
            detail.onCopyPID = { [weak self] pid in self?.copyPID(pid) }
            detail.onAction = { [weak self] entry, action in
                self?.confirmAndPerform(entry: entry, action: action)
            }
            page = detail
        }

        page.onBack = { [weak self] in self?.popProcessPage() }
        let controller = NSViewController()
        controller.view = page
        return controller
    }

    private func popProcessPage() {
        guard !isProcessTransitioning,
              let source = processPageControllers.popLast() else { return }

        let returnFocus = processPageReturnFocusViews.popLast() ?? nil
        _ = processNavigation.goBack()
        let destination = processPageControllers.last ?? overviewPageController
        destination.view.frame = source.view.frame
        destination.view.autoresizingMask = [.width, .height]
        if let page = destination.view as? ProcessPageView,
           let updating = page as? ProcessPageUpdating {
            updating.update(groups: groups(for: page.resource))
        }
        let options = processTransitionOptions(forward: false)
        let completion = { [weak self, weak source] in
            guard let self else { return }
            source?.removeFromParent()
            self.isProcessTransitioning = false
            if self.pendingProcessNavigationReset {
                self.resetProcessNavigation()
                self.adjustPreferredSize()
                return
            }
            if self.processNavigation.isAtOverview {
                self.adjustPreferredSize(preservingVisibleSize: true)
            }
            if let window = destination.view.window,
               let returnFocus,
               returnFocus.window === window,
               window.makeFirstResponder(returnFocus) {
                NSAccessibility.post(element: returnFocus, notification: .focusedUIElementChanged)
            } else {
                self.focusProcessPage(destination)
            }
        }
        if options.isEmpty {
            let parent = source.view.superview ?? navigationContainer
            source.view.removeFromSuperview()
            parent?.addSubview(destination.view)
            completion()
        } else {
            isProcessTransitioning = true
            transition(from: source,
                       to: destination,
                       options: options,
                       completionHandler: completion)
        }
    }

    private func processTransitionOptions(forward: Bool) -> NSViewController.TransitionOptions {
        let shouldAnimate = view.window?.isVisible == true
            && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        guard shouldAnimate else { return [] }
        return forward ? .slideForward : .slideBackward
    }

    private func focusProcessPage(_ controller: NSViewController) {
        guard controller.view.window?.isVisible == true else { return }
        if let page = controller.view as? ProcessPageUpdating {
            controller.view.window?.makeFirstResponder(page.preferredFocusView)
            NSAccessibility.post(element: controller.view, notification: .layoutChanged)
        } else {
            controller.view.window?.makeFirstResponder(scrollView)
            NSAccessibility.post(element: scrollView, notification: .layoutChanged)
        }
    }

    private func updateVisibleProcessPage(for resource: ProcessMonitor.Resource) {
        guard processNavigation.current?.resource == resource,
              let page = processPageControllers.last?.view as? ProcessPageUpdating else { return }
        page.update(groups: groups(for: resource))
    }

    private func groups(for resource: ProcessMonitor.Resource) -> [ProcessMonitor.Group] {
        switch resource {
        case .cpu: return allGroups
        case .memory: return allMemoryGroups
        }
    }

    private func resetProcessNavigation() {
        if isProcessTransitioning {
            pendingProcessNavigationReset = true
            return
        }
        pendingProcessNavigationReset = false
        guard !processNavigation.isAtOverview
                || !processPageControllers.isEmpty
                || scrollView.superview == nil else { return }
        for controller in processPageControllers {
            controller.view.removeFromSuperview()
            controller.removeFromParent()
        }
        processPageControllers.removeAll(keepingCapacity: true)
        processPageReturnFocusViews.removeAll(keepingCapacity: true)
        processNavigation.reset()
        isProcessTransitioning = false

        if scrollView.superview == nil, let navigationContainer {
            scrollView.frame = navigationContainer.bounds
            navigationContainer.addSubview(scrollView)
        }
    }

    private func copyPID(_ pid: Int32) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(String(pid), forType: .string)
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
        }
        statusPairRow?.isHidden = !visible.contains(.temperature) && !visible.contains(.power)
        emptyStateCard?.isHidden = !visible.isEmpty
        adjustPreferredSize()
    }

    private func adjustPreferredSize(preservingVisibleSize: Bool = false) {
        rootStack.layoutSubtreeIfNeeded()
        let contentHeight = max(rootStack.fittingSize.height, 80)
        let cappedHeight = min(contentHeight, maximumPopoverHeight())
        let visibleHeight = preferredContentSize.height > 0 ? preferredContentSize.height : cappedHeight
        scrollView.hasVerticalScroller = contentHeight > visibleHeight + 1
        guard processNavigation.isAtOverview else { return }
        if preservingVisibleSize, isViewLoaded, view.window?.isVisible == true { return }
        preferredContentSize = NSSize(width: MacPulseVisualStyle.popoverWidth,
                                      height: cappedHeight)
    }

    func prepareForDisplay(on screen: NSScreen?) {
        preferredScreen = screen
        resetProcessNavigation()
        adjustPreferredSize()
    }

    private func maximumPopoverHeight() -> CGFloat {
        // 不要存取 self.view — 我們可能在 loadView() 內被呼叫到
        // （applyVisibility() → adjustPreferredSize()），此時 self.view
        // 還沒指定，存取 self.view 會觸發 AppKit 重新 invoke loadView()
        // 進入無限遞迴。view 載完之後才從 view.window 拿 screen。
        let screen: NSScreen?
        if isViewLoaded {
            screen = view.window?.screen ?? preferredScreen ?? NSScreen.main
        } else {
            screen = preferredScreen ?? NSScreen.main
        }
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
            swapUsedLabel.stringValue = memory.swapUsedBytes.map {
                "SWAP \(ByteFormatter.size($0))"
            } ?? "SWAP —"
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
        let icon = MacPulseVisualStyle.symbolBadge(
            metric.symbolName,
            color: MacPulseVisualStyle.accentColor(for: metric),
            accessibilityDescription: metric.displayName,
            size: 30
        )
        icon.toolTip = metric.displayName

        let title = NSTextField(labelWithString: metric.displayName)
        title.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        title.textColor = .labelColor
        title.setAccessibilityLabel(metric.displayName)

        var views: [NSView] = [icon, title, NSView()]
        if let valueView { views.append(valueView) }

        let row = NSStackView(views: views)
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 9
        return row
    }

    private func compactHeaderRow(metric: Metric) -> NSStackView {
        let icon = MacPulseVisualStyle.symbolBadge(
            metric.symbolName,
            color: MacPulseVisualStyle.accentColor(for: metric),
            accessibilityDescription: metric.displayName,
            size: 24
        )
        icon.toolTip = metric.displayName

        let title = NSTextField(labelWithString: metric.displayName)
        title.font = NSFont.systemFont(ofSize: 11.5, weight: .semibold)
        title.textColor = .labelColor
        title.lineBreakMode = .byTruncatingTail
        title.setAccessibilityLabel(metric.displayName)

        let row = NSStackView(views: [icon, title, NSView()])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        return row
    }

    private func labelledRow(symbol: String, value: NSTextField) -> NSStackView {
        let title: String
        let symbolName: String
        let color: NSColor
        switch symbol {
        case "↓":
            title = "Download"
            symbolName = "arrow.down"
            color = .systemGreen
            value.setAccessibilityLabel("Download rate")
        case "↑":
            title = "Upload"
            symbolName = "arrow.up"
            color = .systemGreen
            value.setAccessibilityLabel("Upload rate")
        case "R":
            title = "Read"
            symbolName = "arrow.down"
            color = .systemOrange
            value.setAccessibilityLabel("Disk read rate")
        case "W":
            title = "Write"
            symbolName = "arrow.up"
            color = .systemOrange
            value.setAccessibilityLabel("Disk write rate")
        default:
            title = symbol
            symbolName = "circle"
            color = .secondaryLabelColor
        }

        let icon = MacPulseVisualStyle.symbolBadge(symbolName,
                                                   color: color,
                                                   accessibilityDescription: title,
                                                   size: 24)
        let caption = NSTextField(labelWithString: title)
        caption.font = NSFont.systemFont(ofSize: 9.5, weight: .medium)
        caption.textColor = .secondaryLabelColor

        let labels = stack([caption, value], spacing: 1)
        let row = NSStackView(views: [icon, labels])
        row.orientation = .horizontal
        row.spacing = 8
        row.alignment = .centerY
        return row
    }

    private func stack(_ views: [NSView], spacing: CGFloat) -> NSStackView {
        let s = NSStackView(views: views)
        s.orientation = .vertical
        s.alignment = .leading
        s.spacing = spacing
        return s
    }

    private func popoverCard(around content: NSView) -> NSView {
        MacPulseVisualStyle.card(
            around: content,
            insets: NSEdgeInsets(top: 10, left: 12, bottom: 10, right: 12)
        )
    }

    private func iconButton(symbol: String, accessibilityLabel: String, action: Selector) -> NSButton {
        let button = NSButton()
        if let img = NSImage(systemSymbolName: symbol, accessibilityDescription: accessibilityLabel) {
            button.image = img.withSymbolConfiguration(.init(pointSize: 13, weight: .medium))
        }
        button.imagePosition = .imageOnly
        button.target = self
        button.action = action
        button.contentTintColor = .labelColor
        button.setAccessibilityLabel(accessibilityLabel)
        button.translatesAutoresizingMaskIntoConstraints = false
        MacPulseVisualStyle.configureGlassButton(button)
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 30),
            button.heightAnchor.constraint(equalToConstant: 30)
        ])
        return button
    }

    // MARK: - Static factories

    private static func makeValueLabel() -> NSTextField {
        let label = NSTextField(labelWithString: "—")
        label.font = NSFont.monospacedDigitSystemFont(ofSize: 17, weight: .semibold)
        label.textColor = .labelColor
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        label.setContentHuggingPriority(.required, for: .horizontal)
        return label
    }

    private static func makeRateLabel() -> NSTextField {
        let label = NSTextField(labelWithString: "—")
        label.font = NSFont.monospacedDigitSystemFont(ofSize: 14, weight: .semibold)
        label.textColor = .labelColor
        return label
    }

    private static func makeSecondaryLabel() -> NSTextField {
        let label = NSTextField(labelWithString: "")
        label.font = NSFont.monospacedDigitSystemFont(ofSize: 10.5, weight: .regular)
        label.textColor = .secondaryLabelColor
        label.lineBreakMode = .byTruncatingTail
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

/// 行程列表中的一列：左側顯示群組名稱（同名多行程時帶 ×N），
/// 右側顯示加總 CPU 或 RAM，整行可點擊進入詳細頁。
final class ProcessRowControl: NSButton {
    private let nameLabel = NSTextField(labelWithString: "")
    private let valueLabel = NSTextField(labelWithString: "")
    private let chevron = NSImageView()
    private var trackingArea: NSTrackingArea?
    private var group: ProcessMonitor.Group?
    private let resource: ProcessMonitor.Resource
    private var isPointerInside = false
    private var hasPendingUpdate = false
    private var pendingGroup: ProcessMonitor.Group?

    /// 點擊時 callback：傳回該行群組與原列，讓返回時可恢復焦點。
    var onClick: ((ProcessMonitor.Group, NSView) -> Void)?
    var isInteractionActive: Bool { isPointerInside || window?.firstResponder === self }
    var isPointerInteractionActive: Bool { isPointerInside }

    init(resource: ProcessMonitor.Resource = .cpu) {
        self.resource = resource
        super.init(frame: .zero)
        title = ""
        isBordered = false
        target = self
        action = #selector(pressed)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 8
        if #available(macOS 10.15, *) {
            layer?.cornerCurve = .continuous
        }
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel("Process")
        setAccessibilityHelp("Show process details")
        focusRingType = .exterior

        nameLabel.font = NSFont.systemFont(ofSize: 11.5, weight: .medium)
        nameLabel.textColor = .labelColor
        nameLabel.lineBreakMode = .byTruncatingMiddle
        nameLabel.cell?.usesSingleLineMode = true
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        nameLabel.setContentCompressionResistancePriority(.defaultLow - 1, for: .horizontal)
        nameLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)

        valueLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        valueLabel.textColor = .secondaryLabelColor
        valueLabel.alignment = .right
        valueLabel.translatesAutoresizingMaskIntoConstraints = false
        valueLabel.setContentHuggingPriority(.required, for: .horizontal)
        valueLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        if let img = NSImage(systemSymbolName: "chevron.right", accessibilityDescription: nil) {
            chevron.image = img.withSymbolConfiguration(.init(pointSize: 9, weight: .semibold))
        }
        chevron.contentTintColor = .tertiaryLabelColor
        chevron.translatesAutoresizingMaskIntoConstraints = false

        addSubview(nameLabel)
        addSubview(valueLabel)
        addSubview(chevron)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 26),

            nameLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            nameLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            valueLabel.leadingAnchor.constraint(greaterThanOrEqualTo: nameLabel.trailingAnchor, constant: 8),
            valueLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            valueLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 44),

            chevron.leadingAnchor.constraint(equalTo: valueLabel.trailingAnchor, constant: 4),
            chevron.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
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

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard isEnabled, super.hitTest(point) != nil else { return nil }
        return self
    }

    override func mouseEntered(with event: NSEvent) {
        isPointerInside = true
        guard group != nil else { return }
        layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.12).cgColor
    }

    override func mouseExited(with event: NSEvent) {
        isPointerInside = false
        layer?.backgroundColor = nil
        applyPendingUpdateIfNeeded()
    }

    override var acceptsFirstResponder: Bool { true }
    override var focusRingMaskBounds: NSRect { bounds.insetBy(dx: 2, dy: 2) }

    override func drawFocusRingMask() {
        NSBezierPath(roundedRect: focusRingMaskBounds, xRadius: 7, yRadius: 7).fill()
    }

    override func resignFirstResponder() -> Bool {
        let result = super.resignFirstResponder()
        if result { applyPendingUpdateIfNeeded() }
        return result
    }

    func update(_ group: ProcessMonitor.Group?) {
        // Keep the target stable while it is being interacted with, but allow
        // live metric updates when the represented processes have not changed.
        // A missing process is disabled immediately so a stale target cannot run.
        if group == nil {
            if isInteractionActive {
                let name = self.group?.name ?? nameLabel.stringValue
                updateUnavailable(name: name)
                hasPendingUpdate = true
            } else {
                hasPendingUpdate = false
                pendingGroup = nil
                applyUpdate(nil)
            }
            return
        }
        if isInteractionActive,
           !Self.representsSameProcesses(self.group, group) {
            pendingGroup = group
            hasPendingUpdate = true
            return
        }
        applyUpdate(group)
    }

    private static func representsSameProcesses(_ current: ProcessMonitor.Group?,
                                                 _ update: ProcessMonitor.Group?) -> Bool {
        guard let current, let update, current.name == update.name else { return false }
        return Set(current.entries.map(ProcessEntryID.init))
            == Set(update.entries.map(ProcessEntryID.init))
    }

    func updateUnavailable(name: String) {
        group = nil
        isEnabled = false
        nameLabel.stringValue = name
        valueLabel.stringValue = "Unavailable"
        chevron.isHidden = true
        isHidden = false
        toolTip = "No longer in the current process list"
        setAccessibilityLabel("\(name), unavailable")
        setAccessibilityValue(nil)
        setAccessibilityHelp("No longer in the current process list")
    }

    @objc private func pressed() {
        guard let group else { return }
        onClick?(group, self)
    }

    private func applyPendingUpdateIfNeeded() {
        guard hasPendingUpdate, !isInteractionActive else { return }
        hasPendingUpdate = false
        let update = pendingGroup
        pendingGroup = nil
        applyUpdate(update)
    }

    private func applyUpdate(_ group: ProcessMonitor.Group?) {
        self.group = group
        if let group {
            isEnabled = true
            let suffix = group.count > 1 ? " ×\(group.count)" : ""
            nameLabel.stringValue = group.name + suffix
            valueLabel.stringValue = resource.formattedValue(for: group)
            chevron.isHidden = false
            isHidden = false
            toolTip = Self.tooltip(for: group, resource: resource)
            setAccessibilityLabel(group.count > 1
                ? "\(group.name), \(group.count) processes"
                : "\(group.name), PID \(group.entries[0].pid)")
            setAccessibilityValue(resource.accessibilityValue(for: group))
            setAccessibilityHelp("Show details for \(group.name)")
        } else {
            isEnabled = false
            nameLabel.stringValue = "—"
            valueLabel.stringValue = ""
            chevron.isHidden = true
            isHidden = true
            toolTip = nil
            setAccessibilityLabel("Process")
            setAccessibilityValue(nil)
            setAccessibilityHelp("No process")
        }
    }

    private static func tooltip(for group: ProcessMonitor.Group,
                                resource: ProcessMonitor.Resource) -> String {
        if group.entries.count == 1 {
            let entry = group.entries[0]
            return "\(entry.command)\nPID \(entry.pid)\n\(resource.label) \(resource.formattedValue(for: entry))"
        }
        var lines = ["\(group.name) — \(group.count) processes · \(resource.label) \(resource.formattedValue(for: group))"]
        for entry in group.entries.prefix(8) {
            lines.append("PID \(entry.pid) · \(resource.formattedValue(for: entry))")
        }
        if group.entries.count > 8 {
            lines.append("… and \(group.entries.count - 8) more")
        }
        return lines.joined(separator: "\n")
    }
}

extension ProcessMonitor.Resource {
    var label: String {
        switch self {
        case .cpu: return "CPU"
        case .memory: return "RAM"
        }
    }

    func formattedValue(for group: ProcessMonitor.Group) -> String {
        switch self {
        case .cpu: return String(format: "%.1f%%", group.totalCpuPercent)
        case .memory: return ByteFormatter.size(group.totalMemoryBytes)
        }
    }

    func formattedValue(for entry: ProcessMonitor.Entry) -> String {
        switch self {
        case .cpu: return String(format: "%.1f%%", entry.cpuPercent)
        case .memory: return ByteFormatter.size(entry.memoryBytes)
        }
    }

    func accessibilityValue(for group: ProcessMonitor.Group) -> String {
        switch self {
        case .cpu:
            return String(format: "%.1f percent CPU", group.totalCpuPercent)
        case .memory:
            return "\(ByteFormatter.size(group.totalMemoryBytes)) resident memory"
        }
    }
}

private final class FlippedDocumentView: NSView {
    override var isFlipped: Bool { true }
}
