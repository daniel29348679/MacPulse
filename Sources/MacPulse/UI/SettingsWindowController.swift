import AppKit

final class SettingsWindowController: NSWindowController, NSWindowDelegate {

    static let shared = SettingsWindowController()

    private var menuBarCheckboxes: [Metric: NSButton] = [:]
    private var popoverCheckboxes: [Metric: NSButton] = [:]
    private var intervalSegment: NSSegmentedControl!
    private var sparklineWindowSegment: NSSegmentedControl!
    private var topProcessSegment: NSSegmentedControl!
    private var launchAtLoginCheckbox: NSButton!

    // Update UI
    private var updateButton: NSButton!
    private var updateStatusLabel: NSTextField!
    private var pendingRelease: Updater.Release?
    private enum UpdateUIState {
        case idle
        case checking
        case upToDate
        case available(Updater.Release)
        case installing
        case error(String)
    }
    private var updateState: UpdateUIState = .idle {
        didSet { applyUpdateState() }
    }

    private convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 760),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "MacPulse Settings"
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 520, height: 560)
        window.tabbingMode = .disallowed
        // Always surface on the user's current Space, not the one where the
        // window was last shown — important for menu-bar apps where the user
        // expects "Settings" to follow them across desktops.
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        window.center()

        self.init(window: window)
        window.delegate = self
        window.contentView = buildContentView()
    }

    func show() {
        if !(window?.isVisible ?? false) {
            window?.center()
        }
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        refresh()
    }

    // MARK: - Layout

    private func buildContentView() -> NSView {
        let brandIcon = MacPulseVisualStyle.symbolBadge(
            "waveform.path.ecg",
            color: .controlAccentColor,
            accessibilityDescription: "MacPulse",
            size: 42
        )
        let title = NSTextField(labelWithString: "MacPulse")
        title.font = NSFont.systemFont(ofSize: 24, weight: .bold)

        let subtitle = NSTextField(labelWithString: "A clear, live view of your Mac.")
        subtitle.font = NSFont.systemFont(ofSize: 11.5, weight: .regular)
        subtitle.textColor = .secondaryLabelColor

        let titleStack = NSStackView(views: [title, subtitle])
        titleStack.orientation = .vertical
        titleStack.alignment = .leading
        titleStack.spacing = 2

        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
        let headerVersion = NSTextField(labelWithString: "v\(version)")
        headerVersion.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        headerVersion.textColor = .tertiaryLabelColor

        let header = NSStackView(views: [brandIcon, titleStack, NSView(), headerVersion])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 11

        // Monitoring cadence
        let labels = Settings.allowedIntervals.map(Settings.intervalLabel)
        intervalSegment = NSSegmentedControl(labels: labels, trackingMode: .selectOne, target: self, action: #selector(intervalChanged(_:)))
        intervalSegment.segmentStyle = .rounded
        intervalSegment.translatesAutoresizingMaskIntoConstraints = false
        intervalSegment.widthAnchor.constraint(equalToConstant: 200).isActive = true

        let sparkLabels = Settings.allowedSparklineWindows.map(Settings.sparklineWindowLabel)
        sparklineWindowSegment = NSSegmentedControl(labels: sparkLabels,
                                                    trackingMode: .selectOne,
                                                    target: self,
                                                    action: #selector(sparklineWindowChanged(_:)))
        sparklineWindowSegment.segmentStyle = .rounded
        sparklineWindowSegment.translatesAutoresizingMaskIntoConstraints = false
        sparklineWindowSegment.widthAnchor.constraint(equalToConstant: 200).isActive = true

        let topProcessLabels = Settings.allowedTopProcessCounts.map { "\($0)" }
        topProcessSegment = NSSegmentedControl(labels: topProcessLabels,
                                               trackingMode: .selectOne,
                                               target: self,
                                               action: #selector(topProcessCountChanged(_:)))
        topProcessSegment.segmentStyle = .rounded
        topProcessSegment.translatesAutoresizingMaskIntoConstraints = false
        topProcessSegment.widthAnchor.constraint(equalToConstant: 200).isActive = true

        let intervalRow = preferenceRow(
            symbol: "timer",
            title: "Update Interval",
            detail: "How often MacPulse refreshes live readings.",
            color: .systemBlue,
            control: intervalSegment
        )
        let historyRow = preferenceRow(
            symbol: "chart.xyaxis.line",
            title: "Chart History",
            detail: "The time range kept in each sparkline.",
            color: .systemTeal,
            control: sparklineWindowSegment
        )
        let processesRow = preferenceRow(
            symbol: "list.number",
            title: "Top Processes",
            detail: "Number of processes shown inside the CPU card.",
            color: .systemOrange,
            control: topProcessSegment
        )
        let monitoringContent = fullWidthStack(
            [intervalRow, divider(), historyRow, divider(), processesRow],
            spacing: 10
        )
        let monitoringCard = settingsCard(title: "Monitoring",
                                          symbol: "speedometer",
                                          color: .systemBlue,
                                          content: monitoringContent)

        // Menu bar metrics
        let menuBarStack = NSStackView()
        menuBarStack.orientation = .vertical
        menuBarStack.alignment = .leading
        menuBarStack.spacing = 7
        for metric in Metric.allCases {
            let cb = checkbox(for: metric,
                              scope: "menu bar",
                              action: #selector(menuBarToggled(_:)))
            menuBarCheckboxes[metric] = cb
            menuBarStack.addArrangedSubview(cb)
        }

        // Popover metrics
        let popoverStack = NSStackView()
        popoverStack.orientation = .vertical
        popoverStack.alignment = .leading
        popoverStack.spacing = 7
        for metric in Metric.allCases {
            let cb = checkbox(for: metric,
                              scope: "popover",
                              action: #selector(popoverToggled(_:)))
            popoverCheckboxes[metric] = cb
            popoverStack.addArrangedSubview(cb)
        }

        let menuBarColumn = metricColumn(title: "Menu Bar",
                                         symbol: "menubar.rectangle",
                                         content: menuBarStack)
        let popoverColumn = metricColumn(title: "Popover",
                                         symbol: "rectangle.on.rectangle",
                                         content: popoverStack)
        let twoColumns = NSStackView(views: [
            menuBarColumn,
            popoverColumn
        ])
        twoColumns.orientation = .horizontal
        twoColumns.alignment = .top
        twoColumns.distribution = .fillEqually
        twoColumns.spacing = 28
        let visibilityCard = settingsCard(title: "Visible Metrics",
                                          symbol: "eye",
                                          color: .systemPurple,
                                          content: twoColumns)

        // Startup
        launchAtLoginCheckbox = NSButton(checkboxWithTitle: "",
                                         target: self,
                                         action: #selector(launchAtLoginToggled(_:)))
        launchAtLoginCheckbox.setAccessibilityLabel("Launch MacPulse at login")
        let startupRow = preferenceRow(
            symbol: "power",
            title: "Launch at Login",
            detail: "Start MacPulse automatically when you sign in.",
            color: .systemGreen,
            control: launchAtLoginCheckbox
        )

        // Updates
        updateButton = NSButton(title: "Check for Updates", target: self, action: #selector(updateButtonClicked))
        updateButton.image = NSImage(systemSymbolName: "arrow.triangle.2.circlepath",
                                     accessibilityDescription: nil)
        updateButton.imagePosition = .imageLeading
        updateButton.imageHugsTitle = true
        MacPulseVisualStyle.configureGlassButton(updateButton, primary: true, controlSize: .large)
        updateButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        updateStatusLabel = NSTextField(labelWithString: "")
        updateStatusLabel.font = NSFont.systemFont(ofSize: 10.5, weight: .regular)
        updateStatusLabel.textColor = .secondaryLabelColor
        updateStatusLabel.lineBreakMode = .byWordWrapping
        updateStatusLabel.maximumNumberOfLines = 2

        let updateText = NSStackView(views: [
            label("Software Update", size: 11.5, weight: .semibold, color: .labelColor),
            updateStatusLabel
        ])
        updateText.orientation = .vertical
        updateText.alignment = .leading
        updateText.spacing = 2
        updateText.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let updateIcon = MacPulseVisualStyle.symbolBadge("arrow.down.app",
                                                         color: .systemIndigo,
                                                         accessibilityDescription: "Software Update",
                                                         size: 28)
        let updateRow = NSStackView(views: [updateIcon, updateText, NSView(), updateButton])
        updateRow.orientation = .horizontal
        updateRow.alignment = .centerY
        updateRow.spacing = 10

        let generalContent = fullWidthStack([startupRow, divider(), updateRow], spacing: 10)
        let generalCard = settingsCard(title: "General",
                                       symbol: "gearshape",
                                       color: .systemGreen,
                                       content: generalContent)

        // Footer
        let versionLabel = NSTextField(labelWithString: "v\(version) · MIT License")
        versionLabel.font = NSFont.systemFont(ofSize: 10.5, weight: .regular)
        versionLabel.textColor = .tertiaryLabelColor

        let repoLink = NSButton(title: "View on GitHub", target: self, action: #selector(openRepo))
        repoLink.image = NSImage(systemSymbolName: "arrow.up.right.square",
                                 accessibilityDescription: nil)
        repoLink.imagePosition = .imageLeading
        repoLink.imageHugsTitle = true
        MacPulseVisualStyle.configureGlassButton(repoLink)

        let footer = NSStackView(views: [versionLabel, NSView(), repoLink])
        footer.orientation = .horizontal
        footer.alignment = .centerY

        let rootViews: [NSView] = [header, monitoringCard, visibilityCard, generalCard, footer]
        let mainStack = NSStackView(views: rootViews)
        mainStack.orientation = .vertical
        mainStack.alignment = .leading
        mainStack.spacing = 12
        mainStack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 18, right: 20)
        mainStack.translatesAutoresizingMaskIntoConstraints = false

        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.verticalScrollElasticity = .allowed
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        let document = SettingsDocumentView()
        document.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(mainStack)
        scrollView.documentView = document

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 560, height: 760))
        container.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: container.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor),

            document.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            document.trailingAnchor.constraint(equalTo: scrollView.contentView.trailingAnchor),
            document.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
            document.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),

            mainStack.leadingAnchor.constraint(equalTo: document.leadingAnchor),
            mainStack.trailingAnchor.constraint(equalTo: document.trailingAnchor),
            mainStack.topAnchor.constraint(equalTo: document.topAnchor),
            mainStack.bottomAnchor.constraint(equalTo: document.bottomAnchor)
        ])
        for view in rootViews {
            view.translatesAutoresizingMaskIntoConstraints = false
            view.widthAnchor.constraint(equalTo: mainStack.widthAnchor, constant: -40).isActive = true
        }
        return container
    }

    private func settingsCard(title: String,
                              symbol: String,
                              color: NSColor,
                              content: NSView) -> NSView {
        let icon = MacPulseVisualStyle.symbolBadge(symbol,
                                                   color: color,
                                                   accessibilityDescription: title,
                                                   size: 28)
        let titleLabel = label(title, size: 13, weight: .semibold, color: .labelColor)
        let header = NSStackView(views: [icon, titleLabel, NSView()])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 9

        let body = fullWidthStack([header, content], spacing: 12)
        return MacPulseVisualStyle.card(around: body)
    }

    private func preferenceRow(symbol: String,
                               title: String,
                               detail: String,
                               color: NSColor,
                               control: NSView) -> NSStackView {
        let icon = MacPulseVisualStyle.symbolBadge(symbol,
                                                   color: color,
                                                   accessibilityDescription: title,
                                                   size: 28)
        let titleLabel = label(title, size: 11.5, weight: .semibold, color: .labelColor)
        let detailLabel = label(detail, size: 9.5, weight: .regular, color: .secondaryLabelColor)
        detailLabel.maximumNumberOfLines = 2
        detailLabel.lineBreakMode = .byWordWrapping

        let labels = NSStackView(views: [titleLabel, detailLabel])
        labels.orientation = .vertical
        labels.alignment = .leading
        labels.spacing = 2
        labels.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        control.setContentCompressionResistancePriority(.required, for: .horizontal)

        let row = NSStackView(views: [icon, labels, NSView(), control])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10
        return row
    }

    private func metricColumn(title: String,
                              symbol: String,
                              content: NSView) -> NSStackView {
        let icon = MacPulseVisualStyle.symbolBadge(symbol,
                                                   color: .systemPurple,
                                                   accessibilityDescription: title,
                                                   size: 24)
        let titleLabel = label(title, size: 11.5, weight: .semibold, color: .labelColor)
        let header = NSStackView(views: [icon, titleLabel, NSView()])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 8

        return fullWidthStack([header, content], spacing: 10)
    }

    private func fullWidthStack(_ views: [NSView], spacing: CGFloat) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = spacing
        for view in views {
            view.translatesAutoresizingMaskIntoConstraints = false
            view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        return stack
    }

    private func label(_ text: String,
                       size: CGFloat,
                       weight: NSFont.Weight,
                       color: NSColor) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = NSFont.systemFont(ofSize: size, weight: weight)
        label.textColor = color
        return label
    }

    private func divider() -> NSBox {
        let box = NSBox()
        box.boxType = .separator
        return box
    }

    private func checkbox(for metric: Metric, scope: String, action: Selector) -> NSButton {
        let button = NSButton(checkboxWithTitle: metric.displayName, target: self, action: action)
        button.identifier = NSUserInterfaceItemIdentifier(metric.rawValue)
        button.controlSize = .regular
        button.toolTip = "Show \(metric.displayName) in \(scope)"
        button.setAccessibilityLabel("Show \(metric.displayName) in \(scope)")
        return button
    }

    // MARK: - Actions

    @objc private func intervalChanged(_ sender: NSSegmentedControl) {
        let idx = sender.selectedSegment
        guard idx >= 0, idx < Settings.allowedIntervals.count else { return }
        Settings.shared.updateInterval = Settings.allowedIntervals[idx]
    }

    @objc private func sparklineWindowChanged(_ sender: NSSegmentedControl) {
        let idx = sender.selectedSegment
        guard idx >= 0, idx < Settings.allowedSparklineWindows.count else { return }
        Settings.shared.sparklineWindowSeconds = Settings.allowedSparklineWindows[idx]
    }

    @objc private func topProcessCountChanged(_ sender: NSSegmentedControl) {
        let idx = sender.selectedSegment
        guard idx >= 0, idx < Settings.allowedTopProcessCounts.count else { return }
        Settings.shared.topProcessCount = Settings.allowedTopProcessCounts[idx]
    }

    @objc private func menuBarToggled(_ sender: NSButton) {
        guard let raw = sender.identifier?.rawValue, let metric = Metric(rawValue: raw) else { return }
        Settings.shared.toggleMenuBar(metric)
    }

    @objc private func popoverToggled(_ sender: NSButton) {
        guard let raw = sender.identifier?.rawValue, let metric = Metric(rawValue: raw) else { return }
        Settings.shared.togglePopover(metric)
    }

    @objc private func launchAtLoginToggled(_ sender: NSButton) {
        let wantOn = sender.state == .on
        do {
            try LoginItem.setEnabled(wantOn)
        } catch {
            // 還原 UI
            sender.state = LoginItem.isEnabled ? .on : .off
            presentError(error, title: "Could not change login item")
        }
    }

    @objc private func openRepo() {
        if let url = URL(string: "https://github.com/daniel29348679/MacPulse") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func updateButtonClicked() {
        switch updateState {
        case .idle, .upToDate, .error:
            checkForUpdates()
        case .available(let release):
            installUpdate(release)
        case .checking, .installing:
            break
        }
    }

    private func checkForUpdates() {
        updateState = .checking
        Updater.fetchLatestRelease { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let release):
                if Updater.isNewer(release.version, than: Updater.currentVersion()) {
                    self.pendingRelease = release
                    self.updateState = .available(release)
                } else {
                    self.updateState = .upToDate
                }
            case .failure(let error):
                self.updateState = .error(error.localizedDescription)
            }
        }
    }

    private func installUpdate(_ release: Updater.Release) {
        guard Updater.isInstallable else {
            // 開發環境跑：開瀏覽器引導使用者下載
            NSWorkspace.shared.open(release.pageURL)
            updateState = .error("Run the bundled MacPulse.app to auto-update. Opening release page instead.")
            return
        }
        updateState = .installing
        Updater.downloadAndInstall(release: release) { [weak self] result in
            guard let self else { return }
            if case .failure(let err) = result {
                self.updateState = .error(err.localizedDescription)
            }
            // 成功時 Updater 自己會 NSApp.terminate，不會走到這。
        }
    }

    private func applyUpdateState() {
        switch updateState {
        case .idle:
            updateButton.title = "Check for Updates"
            updateButton.isEnabled = true
            updateStatusLabel.stringValue = ""
            updateStatusLabel.textColor = .secondaryLabelColor
        case .checking:
            updateButton.title = "Checking…"
            updateButton.isEnabled = false
            updateStatusLabel.stringValue = "Contacting GitHub…"
            updateStatusLabel.textColor = .secondaryLabelColor
        case .upToDate:
            updateButton.title = "Check for Updates"
            updateButton.isEnabled = true
            updateStatusLabel.stringValue = "You're on the latest version (v\(Updater.currentVersion()))."
            updateStatusLabel.textColor = .secondaryLabelColor
        case .available(let release):
            updateButton.title = "Download & Install v\(release.version)"
            updateButton.isEnabled = true
            updateStatusLabel.stringValue = "v\(release.version) is available (currently v\(Updater.currentVersion()))."
            updateStatusLabel.textColor = .controlAccentColor
        case .installing:
            updateButton.title = "Installing…"
            updateButton.isEnabled = false
            updateStatusLabel.stringValue = "Downloading and replacing app — MacPulse will relaunch."
            updateStatusLabel.textColor = .secondaryLabelColor
        case .error(let msg):
            updateButton.title = "Check for Updates"
            updateButton.isEnabled = true
            updateStatusLabel.stringValue = msg
            updateStatusLabel.textColor = .systemRed
        }
    }

    private func presentError(_ error: Error, title: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        if let window {
            alert.beginSheetModal(for: window, completionHandler: nil)
        } else {
            alert.runModal()
        }
    }

    // MARK: - State sync

    private func refresh() {
        let interval = Settings.shared.updateInterval
        if let idx = Settings.allowedIntervals.firstIndex(of: interval) {
            intervalSegment.selectedSegment = idx
        }
        let window = Settings.shared.sparklineWindowSeconds
        if let idx = Settings.allowedSparklineWindows.firstIndex(of: window) {
            sparklineWindowSegment.selectedSegment = idx
        }
        let topCount = Settings.shared.topProcessCount
        if let idx = Settings.allowedTopProcessCounts.firstIndex(of: topCount) {
            topProcessSegment.selectedSegment = idx
        }

        let menuBar = Settings.shared.menuBarMetrics
        let popover = Settings.shared.popoverMetrics
        for (metric, cb) in menuBarCheckboxes {
            cb.state = menuBar.contains(metric) ? .on : .off
        }
        for (metric, cb) in popoverCheckboxes {
            cb.state = popover.contains(metric) ? .on : .off
        }

        // Login item
        if LoginItem.isSupported {
            launchAtLoginCheckbox.isEnabled = true
            launchAtLoginCheckbox.state = LoginItem.isEnabled ? .on : .off
            launchAtLoginCheckbox.toolTip = nil
        } else {
            launchAtLoginCheckbox.isEnabled = false
            launchAtLoginCheckbox.state = .off
            launchAtLoginCheckbox.toolTip = "Only available when MacPulse is run from a .app bundle (e.g. /Applications)."
        }

        // 重置 update UI 但保留剛才檢查到的結果（如果使用者只是切換到別頁再回來的話）
        applyUpdateState()
    }

    func windowWillClose(_ notification: Notification) {
        // Settings 視窗收起時不要結束 app（accessory 模式預設不會，但保險）
    }
}

private final class SettingsDocumentView: NSView {
    override var isFlipped: Bool { true }
}
