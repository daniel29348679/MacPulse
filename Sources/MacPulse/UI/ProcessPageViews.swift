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

/// Task Manager-style table backed by NSTableView so only visible rows create
/// views. A stack containing every PID causes Auto Layout to stall on busy Macs.
final class ProcessTaskManagerPageView: ProcessPageView,
                                        ProcessPageUpdating,
                                        NSTableViewDataSource,
                                        NSTableViewDelegate {
    private let statusLabel = ProcessPageViewFactory.captionLabel()
    private let emptyLabel = ProcessPageViewFactory.emptyLabel("Waiting for process data…")
    private let tableView = NSTableView()
    private let tableScroll = NSScrollView()
    private var sortedEntries: [ProcessMonitor.Entry] = []
    private var sortMetric: ProcessSortMetric = .cpu
    private var ascending = false

    var onSelectEntry: ((ProcessMonitor.Entry, ProcessSortMetric, NSView) -> Void)?

    init(entries: [ProcessMonitor.Entry]) {
        super.init(title: "Processes")

        for metric in ProcessSortMetric.allCases {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(metric.sortKey))
            column.title = metric.label
            column.headerCell.alignment = metric == .name ? .left : .right
            column.sortDescriptorPrototype = NSSortDescriptor(
                key: metric.sortKey,
                ascending: metric == .name
            )
            switch metric {
            case .name:
                column.width = 120
                column.minWidth = 88
                column.resizingMask = .autoresizingMask
            case .cpu:
                column.width = 56
                column.minWidth = 44
                column.maxWidth = 58
            case .memory:
                column.width = 64
                column.minWidth = 58
                column.maxWidth = 76
            case .disk:
                column.width = 68
                column.minWidth = 62
                column.maxWidth = 82
            }
            tableView.addTableColumn(column)
        }

        tableView.delegate = self
        tableView.dataSource = self
        tableView.rowHeight = 34
        tableView.intercellSpacing = NSSize(width: 4, height: 1)
        tableView.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle
        tableView.allowsColumnReordering = false
        tableView.allowsColumnResizing = false
        tableView.allowsMultipleSelection = false
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.backgroundColor = .clear
        tableView.gridStyleMask = []
        tableView.style = .plain
        tableView.setAccessibilityLabel("Processes table")
        tableView.sortDescriptors = [NSSortDescriptor(key: ProcessSortMetric.cpu.sortKey,
                                                      ascending: false)]

        tableScroll.documentView = tableView
        tableScroll.drawsBackground = false
        tableScroll.borderType = .noBorder
        tableScroll.hasVerticalScroller = true
        tableScroll.autohidesScrollers = true
        tableScroll.verticalScrollElasticity = .allowed
        tableScroll.horizontalScrollElasticity = .none

        let note = NSTextField(wrappingLabelWithString:
            "Per-process GPU and network data isn’t available through public macOS APIs.")
        note.font = NSFont.systemFont(ofSize: 9.5)
        note.textColor = .tertiaryLabelColor
        note.alignment = .center
        note.maximumNumberOfLines = 2
        note.setAccessibilityLabel(note.stringValue)

        let body = NSView()
        for child in [statusLabel, tableScroll, emptyLabel, note] {
            child.translatesAutoresizingMaskIntoConstraints = false
            body.addSubview(child)
        }
        NSLayoutConstraint.activate([
            statusLabel.leadingAnchor.constraint(equalTo: body.leadingAnchor, constant: 12),
            statusLabel.trailingAnchor.constraint(equalTo: body.trailingAnchor, constant: -12),
            statusLabel.topAnchor.constraint(equalTo: body.topAnchor, constant: 10),

            tableScroll.leadingAnchor.constraint(equalTo: body.leadingAnchor, constant: 8),
            tableScroll.trailingAnchor.constraint(equalTo: body.trailingAnchor, constant: -8),
            tableScroll.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 7),
            tableScroll.bottomAnchor.constraint(equalTo: note.topAnchor, constant: -7),

            emptyLabel.centerXAnchor.constraint(equalTo: tableScroll.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: tableScroll.centerYAnchor),
            emptyLabel.widthAnchor.constraint(lessThanOrEqualTo: tableScroll.widthAnchor, constant: -24),

            note.leadingAnchor.constraint(equalTo: body.leadingAnchor, constant: 12),
            note.trailingAnchor.constraint(equalTo: body.trailingAnchor, constant: -12),
            note.bottomAnchor.constraint(equalTo: body.bottomAnchor, constant: -8)
        ])
        installContent(body)
        update(entries: entries)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(entries: [ProcessMonitor.Entry]) {
        statusLabel.stringValue = "\(entries.count) processes · Updates live · Click a column to sort"
        sortedEntries = sortMetric.sorted(entries, ascending: ascending)
        tableView.reloadData()
        emptyLabel.isHidden = !entries.isEmpty
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        sortedEntries.count
    }

    func tableView(_ tableView: NSTableView,
                   viewFor tableColumn: NSTableColumn?,
                   row: Int) -> NSView? {
        guard sortedEntries.indices.contains(row), let tableColumn else { return nil }
        let entry = sortedEntries[row]
        let identifier = tableColumn.identifier
        if identifier.rawValue == ProcessSortMetric.name.sortKey {
            let view = tableView.makeView(withIdentifier: identifier, owner: self) as? ProcessNameCellView
                ?? ProcessNameCellView(identifier: identifier)
            view.update(entry)
            return view
        }
        let metric = ProcessSortMetric(sortKey: identifier.rawValue) ?? .cpu
        let view = tableView.makeView(withIdentifier: identifier, owner: self) as? ProcessValueCellView
            ?? ProcessValueCellView(identifier: identifier)
        view.update(metric.formattedValue(for: entry), entry: entry, metric: metric)
        return view
    }

    func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
        guard let descriptor = tableView.sortDescriptors.first,
              let key = descriptor.key,
              let metric = ProcessSortMetric(sortKey: key) else { return }
        sortMetric = metric
        ascending = descriptor.ascending
        sortedEntries = metric.sorted(sortedEntries, ascending: ascending)
        tableView.reloadData()
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        let row = tableView.selectedRow
        guard sortedEntries.indices.contains(row) else { return }
        let entry = sortedEntries[row]
        tableView.deselectRow(row)
        onSelectEntry?(entry, sortMetric, tableView)
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

private final class ProcessNameCellView: NSTableCellView {
    private let nameLabel = NSTextField(labelWithString: "")
    private let pidLabel = NSTextField(labelWithString: "")

    init(identifier: NSUserInterfaceItemIdentifier) {
        super.init(frame: .zero)
        self.identifier = identifier

        nameLabel.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        nameLabel.textColor = .labelColor
        nameLabel.lineBreakMode = .byTruncatingMiddle
        nameLabel.cell?.usesSingleLineMode = true
        pidLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 8.5, weight: .regular)
        pidLabel.textColor = .tertiaryLabelColor

        for label in [nameLabel, pidLabel] {
            label.translatesAutoresizingMaskIntoConstraints = false
            addSubview(label)
        }
        NSLayoutConstraint.activate([
            nameLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            nameLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2),
            nameLabel.topAnchor.constraint(equalTo: topAnchor, constant: 3),
            pidLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            pidLabel.trailingAnchor.constraint(equalTo: nameLabel.trailingAnchor),
            pidLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor),
            pidLabel.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -2)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(_ entry: ProcessMonitor.Entry) {
        nameLabel.stringValue = entry.name
        pidLabel.stringValue = "PID \(entry.pid)"
        toolTip = entry.command
        setAccessibilityLabel("\(entry.name), PID \(entry.pid)")
    }
}

private final class ProcessValueCellView: NSTableCellView {
    private let valueLabel = ProcessPageViewFactory.tableValueLabel()

    init(identifier: NSUserInterfaceItemIdentifier) {
        super.init(frame: .zero)
        self.identifier = identifier
        valueLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(valueLabel)
        NSLayoutConstraint.activate([
            valueLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            valueLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            valueLabel.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(_ value: String,
                entry: ProcessMonitor.Entry,
                metric: ProcessSortMetric) {
        valueLabel.stringValue = value
        setAccessibilityLabel(metric.label)
        setAccessibilityValue(value)
        toolTip = "\(entry.name) · \(metric.label) \(value)"
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
    var sortKey: String {
        switch self {
        case .name: return "name"
        case .cpu: return "cpu"
        case .memory: return "memory"
        case .disk: return "disk"
        }
    }

    init?(sortKey: String) {
        switch sortKey {
        case "name": self = .name
        case "cpu": self = .cpu
        case "memory": self = .memory
        case "disk": self = .disk
        default: return nil
        }
    }

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
