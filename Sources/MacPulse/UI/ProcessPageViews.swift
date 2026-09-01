import AppKit

protocol ProcessPageUpdating: AnyObject {
    var preferredFocusView: NSView { get }
    func update(entries: [ProcessMonitor.Entry])
}

/// Shared page chrome for the full-width process browser.
class ProcessPageView: NSView {
    let contentHost = NSView()
    private let backButton = NSButton(title: "Back", target: nil, action: nil)
    var onBack: (() -> Void)?

    var preferredFocusView: NSView { backButton }

    init(title: String) {
        super.init(frame: .zero)
        autoresizingMask = [.width, .height]
        wantsLayer = true

        if let image = NSImage(systemSymbolName: "chevron.left", accessibilityDescription: nil) {
            backButton.image = image.withSymbolConfiguration(.init(pointSize: 11, weight: .semibold))
        }
        backButton.imagePosition = .imageLeading
        backButton.imageHugsTitle = true
        backButton.isBordered = false
        backButton.bezelStyle = .accessoryBarAction
        backButton.contentTintColor = .controlAccentColor
        backButton.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        backButton.target = self
        backButton.action = #selector(goBack)
        backButton.toolTip = "Back"
        backButton.setAccessibilityLabel("Back")
        backButton.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = NSFont.systemFont(ofSize: 14, weight: .semibold)
        titleLabel.textColor = .labelColor
        titleLabel.alignment = .center
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.cell?.usesSingleLineMode = true
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        titleLabel.setAccessibilityLabel(title)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let header = NSView()
        header.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(backButton)
        header.addSubview(titleLabel)

        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false

        contentHost.translatesAutoresizingMaskIntoConstraints = false
        addSubview(header)
        addSubview(separator)
        addSubview(contentHost)

        NSLayoutConstraint.activate([
            header.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            header.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            header.topAnchor.constraint(equalTo: topAnchor, constant: 7),
            header.heightAnchor.constraint(equalToConstant: 32),

            backButton.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            backButton.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            backButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 62),

            titleLabel.centerXAnchor.constraint(equalTo: header.centerXAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            titleLabel.leadingAnchor.constraint(greaterThanOrEqualTo: backButton.trailingAnchor, constant: 4),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: header.trailingAnchor),

            separator.leadingAnchor.constraint(equalTo: leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: trailingAnchor),
            separator.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 6),

            contentHost.leadingAnchor.constraint(equalTo: leadingAnchor),
            contentHost.trailingAnchor.constraint(equalTo: trailingAnchor),
            contentHost.topAnchor.constraint(equalTo: separator.bottomAnchor),
            contentHost.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func installContent(_ content: NSView) {
        content.translatesAutoresizingMaskIntoConstraints = false
        contentHost.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: contentHost.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: contentHost.trailingAnchor),
            content.topAnchor.constraint(equalTo: contentHost.topAnchor),
            content.bottomAnchor.constraint(equalTo: contentHost.bottomAnchor)
        ])
    }

    @objc private func goBack() { onBack?() }

    override func cancelOperation(_ sender: Any?) { onBack?() }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let characters = event.charactersIgnoringModifiers
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let navigationModifiers = modifiers.intersection([.command, .option, .control])
        if characters == "\u{1b}" || (characters == "[" && navigationModifiers == .command) {
            onBack?()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

private final class ProcessPageScrollView: NSScrollView {
    let contentStack = NSStackView()
    private let document = ProcessPageDocumentView()

    init(spacing: CGFloat = 10) {
        super.init(frame: .zero)
        drawsBackground = false
        borderType = .noBorder
        hasVerticalScroller = true
        autohidesScrollers = true
        verticalScrollElasticity = .allowed
        horizontalScrollElasticity = .none

        contentStack.orientation = .vertical
        contentStack.alignment = .leading
        contentStack.spacing = spacing
        contentStack.edgeInsets = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        contentStack.translatesAutoresizingMaskIntoConstraints = false

        document.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(contentStack)
        documentView = document

        NSLayoutConstraint.activate([
            document.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            document.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            document.topAnchor.constraint(equalTo: contentView.topAnchor),
            document.widthAnchor.constraint(equalTo: contentView.widthAnchor),

            contentStack.leadingAnchor.constraint(equalTo: document.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: document.trailingAnchor),
            contentStack.topAnchor.constraint(equalTo: document.topAnchor),
            contentStack.bottomAnchor.constraint(equalTo: document.bottomAnchor)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func addFullWidthView(_ view: NSView) {
        contentStack.addArrangedSubview(view)
        view.translatesAutoresizingMaskIntoConstraints = false
        view.widthAnchor.constraint(equalTo: contentStack.widthAnchor, constant: -24).isActive = true
    }
}

/// Task Manager-style table. Rows stay stable across samples while their live
/// values update; clicking a column changes the sort order.
final class ProcessTaskManagerPageView: ProcessPageView, ProcessPageUpdating {
    private let statusLabel = ProcessPageViewFactory.captionLabel()
    private let emptyLabel = ProcessPageViewFactory.emptyLabel("Waiting for process data…")
    private let rowsStack = ProcessPageViewFactory.verticalStack(spacing: 1)
    private let scroll = ProcessPageScrollView(spacing: 7)
    private var rowsCard: NSView!
    private var headerButtons: [ProcessSortMetric: NSButton] = [:]
    private var rowsByID: [ProcessEntryID: ProcessTableRowControl] = [:]
    private var orderedIDs: [ProcessEntryID] = []
    private var currentEntries: [ProcessMonitor.Entry] = []
    private var sortMetric: ProcessSortMetric = .cpu
    private var ascending = false

    var onSelectEntry: ((ProcessMonitor.Entry, ProcessSortMetric, NSView) -> Void)?

    init(entries: [ProcessMonitor.Entry]) {
        super.init(title: "Processes")

        let headerRow = NSStackView()
        headerRow.orientation = .horizontal
        headerRow.alignment = .centerY
        headerRow.spacing = ProcessTableColumn.spacing

        for metric in ProcessSortMetric.allCases {
            let button = NSButton(title: metric.label, target: self, action: #selector(changeSort(_:)))
            button.tag = ProcessSortMetric.allCases.firstIndex(of: metric) ?? 0
            button.isBordered = false
            button.bezelStyle = .accessoryBarAction
            button.font = NSFont.systemFont(ofSize: 10.5, weight: .semibold)
            button.contentTintColor = .secondaryLabelColor
            button.alignment = metric == .name ? .left : .right
            button.setAccessibilityHelp("Sort processes by \(metric.label)")
            button.translatesAutoresizingMaskIntoConstraints = false
            if let width = ProcessTableColumn.width(for: metric) {
                button.widthAnchor.constraint(equalToConstant: width).isActive = true
                button.setContentHuggingPriority(.required, for: .horizontal)
            } else {
                button.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            }
            headerButtons[metric] = button
            headerRow.addArrangedSubview(button)
        }
        let chevronSpace = NSView()
        chevronSpace.translatesAutoresizingMaskIntoConstraints = false
        chevronSpace.widthAnchor.constraint(equalToConstant: ProcessTableColumn.chevronWidth).isActive = true
        headerRow.addArrangedSubview(chevronSpace)
        let headerCard = MacPulseVisualStyle.card(
            around: headerRow,
            insets: NSEdgeInsets(top: 5, left: 8, bottom: 5, right: 8)
        )

        rowsCard = MacPulseVisualStyle.card(
            around: rowsStack,
            insets: NSEdgeInsets(top: 5, left: 5, bottom: 5, right: 5)
        )

        let note = NSTextField(wrappingLabelWithString:
            "Per-process GPU and network data isn’t available through public macOS APIs.")
        note.font = NSFont.systemFont(ofSize: 9.5)
        note.textColor = .tertiaryLabelColor
        note.alignment = .center
        note.maximumNumberOfLines = 2
        note.setAccessibilityLabel(note.stringValue)

        scroll.addFullWidthView(statusLabel)
        scroll.addFullWidthView(headerCard)
        scroll.addFullWidthView(rowsCard)
        scroll.addFullWidthView(emptyLabel)
        scroll.addFullWidthView(note)
        installContent(scroll)
        updateHeaderButtons()
        update(entries: entries)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(entries: [ProcessMonitor.Entry]) {
        currentEntries = entries
        statusLabel.stringValue = "\(entries.count) processes · Updates live · Click a column to sort"

        let currentByID = Dictionary(uniqueKeysWithValues: entries.map { (ProcessEntryID($0), $0) })
        let stale = orderedIDs.filter { currentByID[$0] == nil }
        let protectedStale = Set(stale.filter { rowsByID[$0]?.isInteractionActive == true })
        for id in stale {
            if protectedStale.contains(id) {
                rowsByID[id]?.update(nil)
            } else if let row = rowsByID.removeValue(forKey: id) {
                rowsStack.removeArrangedSubview(row)
                row.removeFromSuperview()
            }
        }
        orderedIDs.removeAll { currentByID[$0] == nil && !protectedStale.contains($0) }

        for entry in entries {
            let id = ProcessEntryID(entry)
            guard rowsByID[id] == nil else { continue }
            let row = ProcessTableRowControl(entry: entry)
            row.onClick = { [weak self] entry, anchor in
                guard let self else { return }
                self.onSelectEntry?(entry, self.sortMetric, anchor)
            }
            rowsByID[id] = row
            rowsStack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: rowsStack.widthAnchor).isActive = true
            orderedIDs.append(id)
        }

        for (id, row) in rowsByID {
            row.update(currentByID[id])
        }
        reorderRowsIfPossible(protectedStale: protectedStale)
        rowsCard.isHidden = orderedIDs.isEmpty
        emptyLabel.isHidden = !orderedIDs.isEmpty
    }

    @objc private func changeSort(_ sender: NSButton) {
        guard ProcessSortMetric.allCases.indices.contains(sender.tag) else { return }
        let selected = ProcessSortMetric.allCases[sender.tag]
        if selected == sortMetric {
            ascending.toggle()
        } else {
            sortMetric = selected
            ascending = selected == .name
        }
        updateHeaderButtons()
        reorderRowsIfPossible(protectedStale: [])
    }

    private func updateHeaderButtons() {
        for (metric, button) in headerButtons {
            let active = metric == sortMetric
            button.title = active ? "\(metric.label) \(ascending ? "↑" : "↓")" : metric.label
            button.contentTintColor = active ? .controlAccentColor : .secondaryLabelColor
            button.setAccessibilityValue(active ? (ascending ? "Ascending" : "Descending") : "Not sorted")
        }
    }

    private func reorderRowsIfPossible(protectedStale: Set<ProcessEntryID>) {
        guard protectedStale.isEmpty,
              !rowsByID.values.contains(where: { $0.isPointerInteractionActive }) else { return }
        let desiredIDs = sortMetric.sorted(currentEntries, ascending: ascending).map(ProcessEntryID.init)
        guard desiredIDs != orderedIDs else { return }
        for row in rowsStack.arrangedSubviews { rowsStack.removeArrangedSubview(row) }
        for id in desiredIDs {
            if let row = rowsByID[id] { rowsStack.addArrangedSubview(row) }
        }
        orderedIDs = desiredIDs
    }
}

final class ProcessEntryPageView: ProcessPageView, ProcessPageUpdating {
    private let metric: ProcessSortMetric
    private let entryID: ProcessEntryID
    private let fallbackEntry: ProcessMonitor.Entry
    private let statusLabel = ProcessPageViewFactory.captionLabel()
    private let statusDot = ColorDotView()
    private let selectedValue = ProcessPageViewFactory.largeValueLabel()
    private let selectedCaption = ProcessPageViewFactory.captionLabel()
    private let cpuValue = ProcessPageViewFactory.detailValueLabel()
    private let memoryValue = ProcessPageViewFactory.detailValueLabel()
    private let diskValue = ProcessPageViewFactory.detailValueLabel()
    private let commandLabel = NSTextField(wrappingLabelWithString: "")
    private let copyPIDButton = NSButton(title: "Copy PID", target: nil, action: nil)
    private let quitButton = NSButton(title: "Quit", target: nil, action: nil)
    private let forceKillButton = NSButton(title: "Force Kill", target: nil, action: nil)
    private var currentEntry: ProcessMonitor.Entry?

    var onCopyPID: ((Int32) -> Void)?
    var onAction: ((ProcessMonitor.Entry, StatsPopoverController.ProcessAction) -> Void)?

    init(metric: ProcessSortMetric,
         entry: ProcessMonitor.Entry,
         entries: [ProcessMonitor.Entry]) {
        self.metric = metric
        entryID = ProcessEntryID(entry)
        fallbackEntry = entry
        super.init(title: entry.name)

        let scroll = ProcessPageScrollView()
        statusDot.translatesAutoresizingMaskIntoConstraints = false
        statusDot.widthAnchor.constraint(equalToConstant: 7).isActive = true
        statusDot.heightAnchor.constraint(equalToConstant: 7).isActive = true
        let statusRow = NSStackView(views: [statusDot, statusLabel, NSView()])
        statusRow.orientation = .horizontal
        statusRow.alignment = .centerY
        statusRow.spacing = 5

        let icon = MacPulseVisualStyle.symbolBadge(
            metric.symbolName,
            color: metric.accentColor,
            accessibilityDescription: metric.label,
            size: 34
        )
        let selectedLabels = ProcessPageViewFactory.verticalStack(spacing: 2)
        selectedLabels.addArrangedSubview(selectedValue)
        selectedLabels.addArrangedSubview(selectedCaption)
        let usageRow = NSStackView(views: [icon, selectedLabels, NSView()])
        usageRow.orientation = .horizontal
        usageRow.alignment = .centerY
        usageRow.spacing = 10
        let usageCard = MacPulseVisualStyle.card(around: usageRow)

        let facts = ProcessPageViewFactory.verticalStack(spacing: 8)
        facts.addArrangedSubview(ProcessPageViewFactory.detailRow(title: "CPU", value: cpuValue))
        facts.addArrangedSubview(ProcessPageViewFactory.detailRow(title: "Resident Memory", value: memoryValue))
        facts.addArrangedSubview(ProcessPageViewFactory.detailRow(title: "Disk I/O", value: diskValue))
        let pidValue = ProcessPageViewFactory.detailValueLabel()
        pidValue.stringValue = String(entry.pid)
        facts.addArrangedSubview(ProcessPageViewFactory.detailRow(title: "PID", value: pidValue))
        let factsCard = MacPulseVisualStyle.card(around: facts)

        commandLabel.font = NSFont.monospacedSystemFont(ofSize: 10.5, weight: .regular)
        commandLabel.textColor = .secondaryLabelColor
        commandLabel.maximumNumberOfLines = 4
        commandLabel.lineBreakMode = .byTruncatingMiddle
        commandLabel.isSelectable = true
        commandLabel.setAccessibilityLabel("Command")
        let commandStack = ProcessPageViewFactory.verticalStack(spacing: 6)
        commandStack.addArrangedSubview(ProcessPageViewFactory.sectionLabel("Command"))
        commandStack.addArrangedSubview(commandLabel)
        let commandCard = MacPulseVisualStyle.card(around: commandStack)

        copyPIDButton.target = self
        copyPIDButton.action = #selector(copyPID)
        copyPIDButton.bezelStyle = .rounded
        copyPIDButton.controlSize = .small
        copyPIDButton.setAccessibilityLabel("Copy PID \(entry.pid)")

        quitButton.target = self
        quitButton.action = #selector(quitProcess)
        quitButton.bezelStyle = .rounded
        quitButton.controlSize = .regular
        quitButton.setAccessibilityHelp("Ask this process to quit normally.")

        forceKillButton.target = self
        forceKillButton.action = #selector(forceKillProcess)
        forceKillButton.bezelStyle = .rounded
        forceKillButton.controlSize = .regular
        forceKillButton.hasDestructiveAction = true
        forceKillButton.setAccessibilityHelp("Immediately stop this process. Unsaved work may be lost.")

        let actionRow = NSStackView(views: [quitButton, forceKillButton])
        actionRow.orientation = .horizontal
        actionRow.distribution = .fillEqually
        actionRow.spacing = 8
        let warning = NSTextField(wrappingLabelWithString: "Force Kill may cause unsaved work to be lost.")
        warning.font = NSFont.systemFont(ofSize: 10.5)
        warning.textColor = .secondaryLabelColor
        let actions = ProcessPageViewFactory.verticalStack(spacing: 8)
        actions.addArrangedSubview(copyPIDButton)
        actions.addArrangedSubview(actionRow)
        actions.addArrangedSubview(warning)
        let actionCard = MacPulseVisualStyle.card(around: actions)

        scroll.addFullWidthView(statusRow)
        for card in [usageCard, factsCard, commandCard, actionCard] { scroll.addFullWidthView(card) }
        installContent(scroll)
        update(entries: entries)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(entries: [ProcessMonitor.Entry]) {
        let entry = entryID.resolve(in: entries)
        currentEntry = entry

        if let entry {
            statusDot.color = .systemGreen
            statusLabel.stringValue = "Live · Updates automatically"
            selectedValue.stringValue = metric.formattedValue(for: entry)
            selectedCaption.stringValue = metric.detailLabel
            cpuValue.stringValue = String(format: "%.1f%%", entry.cpuPercent)
            memoryValue.stringValue = ByteFormatter.size(entry.memoryBytes)
            diskValue.stringValue = ByteFormatter.rate(entry.diskBytesPerSecond)
            commandLabel.stringValue = entry.command
            commandLabel.toolTip = entry.command
            quitButton.isEnabled = true
            forceKillButton.isEnabled = true
        } else {
            statusDot.color = .systemOrange
            statusLabel.stringValue = "Process is no longer running"
            selectedValue.stringValue = "—"
            selectedCaption.stringValue = "Usage unavailable"
            cpuValue.stringValue = "—"
            memoryValue.stringValue = "—"
            diskValue.stringValue = "—"
            commandLabel.stringValue = fallbackEntry.command
            commandLabel.toolTip = fallbackEntry.command
            quitButton.isEnabled = false
            forceKillButton.isEnabled = false
        }
        setAccessibilityLabel("\(fallbackEntry.name), PID \(fallbackEntry.pid), \(statusLabel.stringValue)")
    }

    @objc private func copyPID() {
        onCopyPID?(entryID.pid)
        copyPIDButton.title = "Copied"
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            self?.copyPIDButton.title = "Copy PID"
        }
    }

    @objc private func quitProcess() {
        guard let currentEntry else { return }
        onAction?(currentEntry, .quit)
    }

    @objc private func forceKillProcess() {
        guard let currentEntry else { return }
        onAction?(currentEntry, .forceKill)
    }
}

private enum ProcessTableColumn {
    static let spacing: CGFloat = 5
    static let chevronWidth: CGFloat = 8

    static func width(for metric: ProcessSortMetric) -> CGFloat? {
        switch metric {
        case .name: return nil
        case .cpu: return 42
        case .memory: return 58
        case .disk: return 62
        }
    }
}

final class ProcessTableRowControl: NSButton {
    private let nameLabel = NSTextField(labelWithString: "")
    private let pidLabel = NSTextField(labelWithString: "")
    private let cpuLabel = ProcessPageViewFactory.tableValueLabel()
    private let memoryLabel = ProcessPageViewFactory.tableValueLabel()
    private let diskLabel = ProcessPageViewFactory.tableValueLabel()
    private let chevron = NSImageView()
    private var trackingArea: NSTrackingArea?
    private var isPointerInside = false
    private var entry: ProcessMonitor.Entry?
    private let fallbackEntry: ProcessMonitor.Entry

    var onClick: ((ProcessMonitor.Entry, NSView) -> Void)?
    var isInteractionActive: Bool { isPointerInside || window?.firstResponder === self }
    var isPointerInteractionActive: Bool { isPointerInside }

    init(entry: ProcessMonitor.Entry) {
        fallbackEntry = entry
        self.entry = entry
        super.init(frame: .zero)
        title = ""
        isBordered = false
        target = self
        action = #selector(pressed)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 8
        if #available(macOS 10.15, *) { layer?.cornerCurve = .continuous }
        focusRingType = .exterior
        setAccessibilityRole(.button)
        setAccessibilityHelp("Show process details")

        nameLabel.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        nameLabel.textColor = .labelColor
        nameLabel.lineBreakMode = .byTruncatingMiddle
        nameLabel.cell?.usesSingleLineMode = true
        pidLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 8.5, weight: .regular)
        pidLabel.textColor = .tertiaryLabelColor
        let nameStack = ProcessPageViewFactory.verticalStack(spacing: 0)
        nameStack.addArrangedSubview(nameLabel)
        nameStack.addArrangedSubview(pidLabel)
        nameStack.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        nameStack.setContentHuggingPriority(.defaultLow, for: .horizontal)

        if let image = NSImage(systemSymbolName: "chevron.right", accessibilityDescription: nil) {
            chevron.image = image.withSymbolConfiguration(.init(pointSize: 8, weight: .semibold))
        }
        chevron.contentTintColor = .tertiaryLabelColor
        chevron.translatesAutoresizingMaskIntoConstraints = false
        chevron.widthAnchor.constraint(equalToConstant: ProcessTableColumn.chevronWidth).isActive = true

        let row = NSStackView(views: [nameStack, cpuLabel, memoryLabel, diskLabel, chevron])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = ProcessTableColumn.spacing
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)

        for pair in [(cpuLabel, ProcessSortMetric.cpu),
                     (memoryLabel, ProcessSortMetric.memory),
                     (diskLabel, ProcessSortMetric.disk)] {
            pair.0.widthAnchor.constraint(equalToConstant: ProcessTableColumn.width(for: pair.1) ?? 0).isActive = true
        }
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 36),
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            row.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
        update(entry)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var acceptsFirstResponder: Bool { true }
    override var focusRingMaskBounds: NSRect { bounds.insetBy(dx: 2, dy: 2) }
    override func drawFocusRingMask() {
        NSBezierPath(roundedRect: focusRingMaskBounds, xRadius: 7, yRadius: 7).fill()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: bounds,
                                  options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                  owner: self)
        addTrackingArea(area)
        trackingArea = area
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard isEnabled, super.hitTest(point) != nil else { return nil }
        return self
    }

    override func mouseEntered(with event: NSEvent) {
        isPointerInside = true
        guard entry != nil else { return }
        layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.12).cgColor
    }

    override func mouseExited(with event: NSEvent) {
        isPointerInside = false
        layer?.backgroundColor = nil
    }

    func update(_ entry: ProcessMonitor.Entry?) {
        self.entry = entry
        nameLabel.stringValue = entry?.name ?? fallbackEntry.name
        pidLabel.stringValue = "PID \(fallbackEntry.pid)"
        if let entry {
            isEnabled = true
            cpuLabel.stringValue = String(format: "%.1f%%", entry.cpuPercent)
            memoryLabel.stringValue = ByteFormatter.size(entry.memoryBytes)
            diskLabel.stringValue = ByteFormatter.rate(entry.diskBytesPerSecond)
            chevron.isHidden = false
            toolTip = entry.command
            setAccessibilityLabel("\(entry.name), PID \(entry.pid)")
            setAccessibilityValue("\(cpuLabel.stringValue) CPU, \(memoryLabel.stringValue) RAM, \(diskLabel.stringValue) disk I/O")
        } else {
            isEnabled = false
            cpuLabel.stringValue = "—"
            memoryLabel.stringValue = "—"
            diskLabel.stringValue = "—"
            chevron.isHidden = true
            toolTip = "Process is no longer running"
            setAccessibilityLabel("\(fallbackEntry.name), PID \(fallbackEntry.pid), unavailable")
            setAccessibilityValue(nil)
        }
    }

    @objc private func pressed() {
        guard let entry else { return }
        onClick?(entry, self)
    }
}

private enum ProcessPageViewFactory {
    static func verticalStack(spacing: CGFloat) -> NSStackView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = spacing
        return stack
    }

    static func captionLabel() -> NSTextField {
        let label = NSTextField(labelWithString: "")
        label.font = NSFont.systemFont(ofSize: 10.5, weight: .medium)
        label.textColor = .secondaryLabelColor
        label.lineBreakMode = .byTruncatingTail
        return label
    }

    static func sectionLabel(_ title: String) -> NSTextField {
        let label = NSTextField(labelWithString: title)
        label.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        label.textColor = .secondaryLabelColor
        return label
    }

    static func emptyLabel(_ title: String) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: title)
        label.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        label.textColor = .secondaryLabelColor
        label.alignment = .center
        label.setContentHuggingPriority(.required, for: .vertical)
        return label
    }

    static func largeValueLabel() -> NSTextField {
        let label = NSTextField(labelWithString: "—")
        label.font = NSFont.monospacedDigitSystemFont(ofSize: 20, weight: .semibold)
        label.textColor = .labelColor
        return label
    }

    static func detailValueLabel() -> NSTextField {
        let label = NSTextField(labelWithString: "—")
        label.font = NSFont.monospacedDigitSystemFont(ofSize: 11.5, weight: .medium)
        label.textColor = .labelColor
        label.alignment = .right
        label.setContentHuggingPriority(.required, for: .horizontal)
        return label
    }

    static func tableValueLabel() -> NSTextField {
        let label = NSTextField(labelWithString: "—")
        label.font = NSFont.monospacedDigitSystemFont(ofSize: 9.5, weight: .medium)
        label.textColor = .secondaryLabelColor
        label.alignment = .right
        label.lineBreakMode = .byTruncatingTail
        label.setContentHuggingPriority(.required, for: .horizontal)
        return label
    }

    static func detailRow(title: String, value: NSTextField) -> NSStackView {
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = NSFont.systemFont(ofSize: 11.5, weight: .medium)
        titleLabel.textColor = .secondaryLabelColor
        let row = NSStackView(views: [titleLabel, NSView(), value])
        row.orientation = .horizontal
        row.alignment = .firstBaseline
        row.spacing = 8
        return row
    }
}

private final class ProcessPageDocumentView: NSView {
    override var isFlipped: Bool { true }
}

private extension ProcessSortMetric {
    var symbolName: String {
        switch self {
        case .name: return "list.bullet"
        case .cpu: return "cpu"
        case .memory: return "memorychip"
        case .disk: return "internaldrive"
        }
    }

    var accentColor: NSColor {
        switch self {
        case .name: return .controlAccentColor
        case .cpu: return .systemBlue
        case .memory: return .systemPurple
        case .disk: return .systemOrange
        }
    }

    var detailLabel: String {
        switch self {
        case .name: return "Process"
        case .cpu: return "CPU usage"
        case .memory: return "Resident memory"
        case .disk: return "Disk I/O"
        }
    }

    func formattedValue(for entry: ProcessMonitor.Entry) -> String {
        switch self {
        case .name: return entry.name
        case .cpu: return String(format: "%.1f%%", entry.cpuPercent)
        case .memory: return ByteFormatter.size(entry.memoryBytes)
        case .disk: return ByteFormatter.rate(entry.diskBytesPerSecond)
        }
    }
}
