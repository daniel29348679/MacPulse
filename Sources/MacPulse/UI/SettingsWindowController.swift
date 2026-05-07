import AppKit

final class SettingsWindowController: NSWindowController, NSWindowDelegate {

    static let shared = SettingsWindowController()

    private var menuBarCheckboxes: [Metric: NSButton] = [:]
    private var popoverCheckboxes: [Metric: NSButton] = [:]
    private var intervalSegment: NSSegmentedControl!
    private var sparklineWindowSegment: NSSegmentedControl!
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
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 600),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "MacPulse Settings"
        window.isReleasedWhenClosed = false
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
        let title = NSTextField(labelWithString: "MacPulse")
        title.font = NSFont.systemFont(ofSize: 20, weight: .bold)

        let subtitle = NSTextField(labelWithString: "A tiny native macOS system monitor.")
        subtitle.font = NSFont.systemFont(ofSize: 12, weight: .regular)
        subtitle.textColor = .secondaryLabelColor

        let titleStack = NSStackView(views: [title, subtitle])
        titleStack.orientation = .vertical
        titleStack.alignment = .leading
        titleStack.spacing = 2

        // 更新間隔
        let intervalLabel = sectionTitle("UPDATE INTERVAL")
        let labels = Settings.allowedIntervals.map(Settings.intervalLabel)
        intervalSegment = NSSegmentedControl(labels: labels, trackingMode: .selectOne, target: self, action: #selector(intervalChanged(_:)))
        intervalSegment.segmentStyle = .rounded
        intervalSegment.translatesAutoresizingMaskIntoConstraints = false

        // Sparkline window
        let sparklineLabel = sectionTitle("CHART HISTORY WINDOW")
        let sparkLabels = Settings.allowedSparklineWindows.map(Settings.sparklineWindowLabel)
        sparklineWindowSegment = NSSegmentedControl(labels: sparkLabels,
                                                    trackingMode: .selectOne,
                                                    target: self,
                                                    action: #selector(sparklineWindowChanged(_:)))
        sparklineWindowSegment.segmentStyle = .rounded
        sparklineWindowSegment.translatesAutoresizingMaskIntoConstraints = false

        // Menu bar metrics
        let menuBarLabel = sectionTitle("SHOW IN MENU BAR")
        let menuBarStack = NSStackView()
        menuBarStack.orientation = .vertical
        menuBarStack.alignment = .leading
        menuBarStack.spacing = 6
        for metric in Metric.allCases {
            let cb = checkbox(for: metric, action: #selector(menuBarToggled(_:)))
            menuBarCheckboxes[metric] = cb
            menuBarStack.addArrangedSubview(cb)
        }

        // Popover metrics
        let popoverLabel = sectionTitle("SHOW IN POPOVER")
        let popoverStack = NSStackView()
        popoverStack.orientation = .vertical
        popoverStack.alignment = .leading
        popoverStack.spacing = 6
        for metric in Metric.allCases {
            let cb = checkbox(for: metric, action: #selector(popoverToggled(_:)))
            popoverCheckboxes[metric] = cb
            popoverStack.addArrangedSubview(cb)
        }

        let twoColumns = NSStackView(views: [
            wrap(label: menuBarLabel, content: menuBarStack),
            wrap(label: popoverLabel, content: popoverStack)
        ])
        twoColumns.orientation = .horizontal
        twoColumns.alignment = .top
        twoColumns.distribution = .fillEqually
        twoColumns.spacing = 24

        // Startup
        let startupLabel = sectionTitle("STARTUP")
        launchAtLoginCheckbox = NSButton(checkboxWithTitle: "Launch MacPulse at login",
                                         target: self,
                                         action: #selector(launchAtLoginToggled(_:)))

        // Updates
        let updatesLabel = sectionTitle("UPDATES")
        updateButton = NSButton(title: "Check for Updates", target: self, action: #selector(updateButtonClicked))
        updateButton.bezelStyle = .rounded
        updateStatusLabel = NSTextField(labelWithString: "")
        updateStatusLabel.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        updateStatusLabel.textColor = .secondaryLabelColor
        updateStatusLabel.lineBreakMode = .byWordWrapping
        updateStatusLabel.maximumNumberOfLines = 2

        let updateRow = NSStackView(views: [updateButton, updateStatusLabel])
        updateRow.orientation = .horizontal
        updateRow.alignment = .centerY
        updateRow.spacing = 10

        // Footer
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
        let versionLabel = NSTextField(labelWithString: "v\(version) · MIT License")
        versionLabel.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        versionLabel.textColor = .tertiaryLabelColor

        let repoLink = NSButton(title: "View on GitHub", target: self, action: #selector(openRepo))
        repoLink.bezelStyle = .accessoryBarAction
        repoLink.isBordered = false
        repoLink.contentTintColor = .controlAccentColor
        repoLink.font = NSFont.systemFont(ofSize: 11, weight: .medium)

        let footer = NSStackView(views: [versionLabel, NSView(), repoLink])
        footer.orientation = .horizontal
        footer.alignment = .centerY

        let mainStack = NSStackView(views: [
            titleStack,
            divider(),
            wrap(label: intervalLabel, content: intervalSegment),
            wrap(label: sparklineLabel, content: sparklineWindowSegment),
            divider(),
            twoColumns,
            divider(),
            wrap(label: startupLabel, content: launchAtLoginCheckbox),
            wrap(label: updatesLabel, content: updateRow),
            divider(),
            footer
        ])
        mainStack.orientation = .vertical
        mainStack.alignment = .leading
        mainStack.spacing = 14
        mainStack.edgeInsets = NSEdgeInsets(top: 20, left: 24, bottom: 20, right: 24)
        mainStack.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 440, height: 600))
        container.addSubview(mainStack)
        NSLayoutConstraint.activate([
            mainStack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            mainStack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            mainStack.topAnchor.constraint(equalTo: container.topAnchor),
            mainStack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            intervalSegment.widthAnchor.constraint(equalTo: mainStack.widthAnchor, constant: -48),
            sparklineWindowSegment.widthAnchor.constraint(equalTo: mainStack.widthAnchor, constant: -48),
            footer.widthAnchor.constraint(equalTo: mainStack.widthAnchor, constant: -48)
        ])
        return container
    }

    private func wrap(label: NSView, content: NSView) -> NSStackView {
        let s = NSStackView(views: [label, content])
        s.orientation = .vertical
        s.alignment = .leading
        s.spacing = 8
        return s
    }

    private func sectionTitle(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = NSFont.systemFont(ofSize: 10, weight: .semibold)
        label.textColor = .secondaryLabelColor
        return label
    }

    private func divider() -> NSBox {
        let box = NSBox()
        box.boxType = .separator
        return box
    }

    private func checkbox(for metric: Metric, action: Selector) -> NSButton {
        let button = NSButton(checkboxWithTitle: metric.displayName, target: self, action: action)
        button.identifier = NSUserInterfaceItemIdentifier(metric.rawValue)
        if let img = NSImage(systemSymbolName: metric.symbolName, accessibilityDescription: nil) {
            button.image = img.withSymbolConfiguration(.init(pointSize: 12, weight: .medium))
            button.imagePosition = .imageRight
            button.imageHugsTitle = false
        }
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
