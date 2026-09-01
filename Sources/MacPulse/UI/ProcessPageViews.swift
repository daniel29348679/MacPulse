import AppKit

protocol ProcessPageUpdating: AnyObject {
    var preferredFocusView: NSView { get }
    func update(groups: [ProcessMonitor.Group])
}

/// Shared page chrome: a pinned Back button and a scrollable/content area.
class ProcessPageView: NSView {
    let resource: ProcessMonitor.Resource
    let contentHost = NSView()
    private let backButton = NSButton(title: "Back", target: nil, action: nil)
    var onBack: (() -> Void)?

    var preferredFocusView: NSView { backButton }

    init(title: String, resource: ProcessMonitor.Resource) {
        self.resource = resource
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

    @objc private func goBack() {
        onBack?()
    }

    override func cancelOperation(_ sender: Any?) {
        onBack?()
    }

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

/// A vertically scrolling page body with standard popover insets.
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

final class ProcessListPageView: ProcessPageView, ProcessPageUpdating {
    private let statusLabel = ProcessPageViewFactory.captionLabel()
    private let emptyLabel = ProcessPageViewFactory.emptyLabel("Waiting for process data…")
    private let rowsStack = ProcessPageViewFactory.verticalStack(spacing: 1)
    private let scroll = ProcessPageScrollView()
    private var rowsCard: NSView!
    private var orderedNames: [String] = []
    private var rowsByName: [String: ProcessRowControl] = [:]

    var onSelectGroup: ((ProcessMonitor.Group, NSView) -> Void)?

    init(resource: ProcessMonitor.Resource, groups: [ProcessMonitor.Group]) {
        super.init(title: "\(resource.label) Processes", resource: resource)

        rowsCard = MacPulseVisualStyle.card(
            around: rowsStack,
            insets: NSEdgeInsets(top: 6, left: 6, bottom: 6, right: 6)
        )
        scroll.addFullWidthView(statusLabel)
        scroll.addFullWidthView(rowsCard)
        scroll.addFullWidthView(emptyLabel)
        installContent(scroll)
        update(groups: groups)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(groups: [ProcessMonitor.Group]) {
        let currentByName = Dictionary(uniqueKeysWithValues: groups.map { ($0.name, $0) })

        // Keep surviving rows stable while values update, but remove processes
        // that have exited so the page always describes the current snapshot.
        let stale = orderedNames.filter { currentByName[$0] == nil }
        let protectedStale = Set(stale.filter { rowsByName[$0]?.isInteractionActive == true })
        for name in stale {
            if protectedStale.contains(name) {
                rowsByName[name]?.updateUnavailable(name: name)
                continue
            }
            if let row = rowsByName.removeValue(forKey: name) {
                rowsStack.removeArrangedSubview(row)
                row.removeFromSuperview()
            }
        }
        orderedNames.removeAll { currentByName[$0] == nil && !protectedStale.contains($0) }

        for group in groups where rowsByName[group.name] == nil {
            guard orderedNames.count < ProcessMonitor.hardLimit else { break }
            let row = ProcessRowControl(resource: resource)
            row.onClick = { [weak self] group, anchor in
                self?.onSelectGroup?(group, anchor)
            }
            rowsStack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: rowsStack.widthAnchor).isActive = true
            rowsByName[group.name] = row
            orderedNames.append(group.name)
        }

        let desiredNames = groups.prefix(ProcessMonitor.hardLimit).map(\.name)
        if desiredNames != orderedNames,
           protectedStale.isEmpty,
           !rowsByName.values.contains(where: { $0.isPointerInteractionActive }) {
            for row in rowsStack.arrangedSubviews {
                rowsStack.removeArrangedSubview(row)
            }
            for name in desiredNames {
                if let row = rowsByName[name] { rowsStack.addArrangedSubview(row) }
            }
            orderedNames = desiredNames
        }

        for name in orderedNames {
            if let group = currentByName[name] {
                rowsByName[name]?.update(group)
            } else {
                rowsByName[name]?.updateUnavailable(name: name)
            }
        }

        let processCount = groups.reduce(0) { $0 + $1.count }
        if groups.isEmpty {
            statusLabel.stringValue = "Process usage updates live"
        } else if groups.count == ProcessMonitor.hardLimit {
            statusLabel.stringValue = "Top \(ProcessMonitor.hardLimit) groups · \(processCount) processes · Updates live"
        } else if processCount == groups.count {
            statusLabel.stringValue = "\(processCount) \(processCount == 1 ? "process" : "processes") · Updates live"
        } else {
            statusLabel.stringValue = "\(processCount) processes in \(groups.count) groups · Updates live"
        }
        rowsCard.isHidden = orderedNames.isEmpty
        emptyLabel.isHidden = !orderedNames.isEmpty
    }
}

final class ProcessGroupPageView: ProcessPageView, ProcessPageUpdating {
    private let groupName: String
    private let summaryValue = ProcessPageViewFactory.largeValueLabel()
    private let summaryDetail = ProcessPageViewFactory.captionLabel()
    private let memberHeading = ProcessPageViewFactory.sectionLabel("Processes")
    private let emptyLabel = ProcessPageViewFactory.emptyLabel("No members in the current list")
    private let rowsStack = ProcessPageViewFactory.verticalStack(spacing: 1)
    private let scroll = ProcessPageScrollView()
    private var rowsCard: NSView!
    private var orderedIDs: [ProcessEntryID] = []
    private var rowsByID: [ProcessEntryID: ProcessEntryRowControl] = [:]

    var onSelectEntry: ((ProcessMonitor.Entry, NSView) -> Void)?

    init(resource: ProcessMonitor.Resource,
         groupName: String,
         groups: [ProcessMonitor.Group]) {
        self.groupName = groupName
        super.init(title: groupName, resource: resource)

        let icon = MacPulseVisualStyle.symbolBadge(
            resource.symbolName,
            color: resource.accentColor,
            accessibilityDescription: resource.label,
            size: 32
        )
        let labels = ProcessPageViewFactory.verticalStack(spacing: 2)
        labels.addArrangedSubview(summaryValue)
        labels.addArrangedSubview(summaryDetail)
        let summaryRow = NSStackView(views: [icon, labels, NSView()])
        summaryRow.orientation = .horizontal
        summaryRow.alignment = .centerY
        summaryRow.spacing = 10
        let summaryCard = MacPulseVisualStyle.card(around: summaryRow)

        rowsCard = MacPulseVisualStyle.card(
            around: rowsStack,
            insets: NSEdgeInsets(top: 6, left: 6, bottom: 6, right: 6)
        )
        scroll.addFullWidthView(summaryCard)
        scroll.addFullWidthView(memberHeading)
        scroll.addFullWidthView(rowsCard)
        scroll.addFullWidthView(emptyLabel)
        installContent(scroll)
        update(groups: groups)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(groups: [ProcessMonitor.Group]) {
        guard let group = groups.first(where: { $0.name == groupName }) else {
            summaryValue.stringValue = "—"
            summaryDetail.stringValue = "No longer in the current process list"
            let protected = Set(orderedIDs.filter { rowsByID[$0]?.isInteractionActive == true })
            for id in orderedIDs {
                if protected.contains(id) {
                    rowsByID[id]?.update(nil)
                } else if let row = rowsByID.removeValue(forKey: id) {
                    rowsStack.removeArrangedSubview(row)
                    row.removeFromSuperview()
                }
            }
            orderedIDs.removeAll { !protected.contains($0) }
            rowsCard.isHidden = orderedIDs.isEmpty
            emptyLabel.isHidden = !orderedIDs.isEmpty
            return
        }

        summaryValue.stringValue = resource.formattedValue(for: group)
        summaryDetail.stringValue = group.count == 1
            ? "1 process · Updates live"
            : "\(group.count) processes · Updates live"
        memberHeading.stringValue = group.count == 1 ? "Process" : "Processes"

        let currentByID = Dictionary(uniqueKeysWithValues: group.entries.map { (ProcessEntryID($0), $0) })
        let stale = orderedIDs.filter { currentByID[$0] == nil }
        let protectedStale = Set(stale.filter { rowsByID[$0]?.isInteractionActive == true })
        for id in stale {
            if protectedStale.contains(id) {
                rowsByID[id]?.update(nil)
                continue
            }
            if let row = rowsByID.removeValue(forKey: id) {
                rowsStack.removeArrangedSubview(row)
                row.removeFromSuperview()
            }
        }
        orderedIDs.removeAll { currentByID[$0] == nil && !protectedStale.contains($0) }

        for entry in group.entries {
            let id = ProcessEntryID(entry)
            guard rowsByID[id] == nil else { continue }
            let row = ProcessEntryRowControl(resource: resource, entry: entry)
            row.onClick = { [weak self] entry, anchor in
                self?.onSelectEntry?(entry, anchor)
            }
            rowsStack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: rowsStack.widthAnchor).isActive = true
            rowsByID[id] = row
            orderedIDs.append(id)
        }

        let desiredIDs = group.entries.map(ProcessEntryID.init)
        if desiredIDs != orderedIDs,
           protectedStale.isEmpty,
           !rowsByID.values.contains(where: { $0.isPointerInteractionActive }) {
            for row in rowsStack.arrangedSubviews {
                rowsStack.removeArrangedSubview(row)
            }
            for id in desiredIDs {
                if let row = rowsByID[id] { rowsStack.addArrangedSubview(row) }
            }
            orderedIDs = desiredIDs
        }

        for id in orderedIDs {
            rowsByID[id]?.update(currentByID[id])
        }
        rowsCard.isHidden = orderedIDs.isEmpty
        emptyLabel.isHidden = !orderedIDs.isEmpty
    }
}

final class ProcessEntryPageView: ProcessPageView, ProcessPageUpdating {
    private let groupName: String
    private let entryID: ProcessEntryID
    private let fallbackEntry: ProcessMonitor.Entry
    private let statusLabel = ProcessPageViewFactory.captionLabel()
    private let statusDot = ColorDotView()
    private let selectedValue = ProcessPageViewFactory.largeValueLabel()
    private let selectedCaption = ProcessPageViewFactory.captionLabel()
    private let cpuValue = ProcessPageViewFactory.detailValueLabel()
    private let memoryValue = ProcessPageViewFactory.detailValueLabel()
    private let commandLabel = NSTextField(wrappingLabelWithString: "")
    private let copyPIDButton = NSButton(title: "Copy PID", target: nil, action: nil)
    private let quitButton = NSButton(title: "Quit", target: nil, action: nil)
    private let forceKillButton = NSButton(title: "Force Kill", target: nil, action: nil)
    private var currentEntry: ProcessMonitor.Entry?

    var onCopyPID: ((Int32) -> Void)?
    var onAction: ((ProcessMonitor.Entry, StatsPopoverController.ProcessAction) -> Void)?

    init(resource: ProcessMonitor.Resource,
         groupName: String,
         entry: ProcessMonitor.Entry,
         groups: [ProcessMonitor.Group]) {
        self.groupName = groupName
        entryID = ProcessEntryID(entry)
        fallbackEntry = entry
        super.init(title: entry.name, resource: resource)

        let scroll = ProcessPageScrollView()

        statusDot.translatesAutoresizingMaskIntoConstraints = false
        statusDot.widthAnchor.constraint(equalToConstant: 7).isActive = true
        statusDot.heightAnchor.constraint(equalToConstant: 7).isActive = true
        let statusRow = NSStackView(views: [statusDot, statusLabel, NSView()])
        statusRow.orientation = .horizontal
        statusRow.alignment = .centerY
        statusRow.spacing = 5

        let icon = MacPulseVisualStyle.symbolBadge(
            resource.symbolName,
            color: resource.accentColor,
            accessibilityDescription: resource.label,
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
        let pidValue = ProcessPageViewFactory.detailValueLabel()
        pidValue.stringValue = String(entry.pid)
        let pidRow = ProcessPageViewFactory.detailRow(title: "PID", value: pidValue)
        facts.addArrangedSubview(pidRow)
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
        for card in [usageCard, factsCard, commandCard, actionCard] {
            scroll.addFullWidthView(card)
        }
        installContent(scroll)
        update(groups: groups)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(groups: [ProcessMonitor.Group]) {
        let entry = entryID.resolve(in: groups, groupName: groupName)
        currentEntry = entry

        if let entry {
            statusDot.color = .systemGreen
            statusLabel.stringValue = "Live · Updates automatically"
            selectedValue.stringValue = resource.formattedValue(for: entry)
            selectedCaption.stringValue = resource == .cpu ? "CPU usage" : "Resident memory"
            cpuValue.stringValue = String(format: "%.1f%%", entry.cpuPercent)
            memoryValue.stringValue = ByteFormatter.size(entry.memoryBytes)
            commandLabel.stringValue = entry.command
            commandLabel.toolTip = entry.command
            quitButton.isEnabled = true
            forceKillButton.isEnabled = true
        } else {
            statusDot.color = .systemOrange
            statusLabel.stringValue = "No longer in the current process list"
            selectedValue.stringValue = "—"
            selectedCaption.stringValue = resource == .cpu ? "CPU usage unavailable" : "Memory usage unavailable"
            cpuValue.stringValue = "—"
            memoryValue.stringValue = "—"
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

final class ProcessEntryRowControl: NSButton {
    private let pidLabel = NSTextField(labelWithString: "")
    private let valueLabel = NSTextField(labelWithString: "")
    private let chevron = NSImageView()
    private var trackingArea: NSTrackingArea?
    private var isPointerInside = false
    private var entry: ProcessMonitor.Entry?
    private let resource: ProcessMonitor.Resource
    private let fallbackPID: Int32

    var onClick: ((ProcessMonitor.Entry, NSView) -> Void)?
    var isInteractionActive: Bool { isPointerInside || window?.firstResponder === self }
    var isPointerInteractionActive: Bool { isPointerInside }

    init(resource: ProcessMonitor.Resource, entry: ProcessMonitor.Entry) {
        self.resource = resource
        fallbackPID = entry.pid
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

        pidLabel.font = NSFont.systemFont(ofSize: 11.5, weight: .medium)
        pidLabel.textColor = .labelColor

        valueLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        valueLabel.textColor = .secondaryLabelColor
        valueLabel.alignment = .right
        valueLabel.setContentHuggingPriority(.required, for: .horizontal)

        if let image = NSImage(systemSymbolName: "chevron.right", accessibilityDescription: nil) {
            chevron.image = image.withSymbolConfiguration(.init(pointSize: 9, weight: .semibold))
        }
        chevron.contentTintColor = .tertiaryLabelColor

        for view in [pidLabel, valueLabel, chevron] { view.translatesAutoresizingMaskIntoConstraints = false }
        addSubview(pidLabel)
        addSubview(valueLabel)
        addSubview(chevron)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 30),
            pidLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            pidLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            valueLabel.leadingAnchor.constraint(greaterThanOrEqualTo: pidLabel.trailingAnchor, constant: 8),
            valueLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            chevron.leadingAnchor.constraint(equalTo: valueLabel.trailingAnchor, constant: 5),
            chevron.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            chevron.centerYAnchor.constraint(equalTo: centerYAnchor),
            chevron.widthAnchor.constraint(equalToConstant: 10)
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
        pidLabel.stringValue = "PID \(fallbackPID)"
        if let entry {
            isEnabled = true
            valueLabel.stringValue = resource.formattedValue(for: entry)
            chevron.isHidden = false
            toolTip = entry.command
            setAccessibilityLabel("PID \(entry.pid)")
            setAccessibilityValue(resource.accessibilityValue(for: entry))
        } else {
            isEnabled = false
            valueLabel.stringValue = "Unavailable"
            chevron.isHidden = true
            toolTip = "No longer in the current process list"
            setAccessibilityLabel("PID \(fallbackPID), unavailable")
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

extension ProcessMonitor.Resource {
    var symbolName: String {
        switch self {
        case .cpu: return "cpu"
        case .memory: return "memorychip"
        }
    }

    var accentColor: NSColor {
        switch self {
        case .cpu: return .systemBlue
        case .memory: return .systemPurple
        }
    }

    func accessibilityValue(for entry: ProcessMonitor.Entry) -> String {
        switch self {
        case .cpu: return String(format: "%.1f percent CPU", entry.cpuPercent)
        case .memory: return "\(ByteFormatter.size(entry.memoryBytes)) resident memory"
        }
    }
}
