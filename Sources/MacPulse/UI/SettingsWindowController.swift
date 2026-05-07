import AppKit

final class SettingsWindowController: NSWindowController, NSWindowDelegate {

    static let shared = SettingsWindowController()

    private var menuBarCheckboxes: [Metric: NSButton] = [:]
    private var popoverCheckboxes: [Metric: NSButton] = [:]
    private var intervalSegment: NSSegmentedControl!

    private convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 460),
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
        let labels = Settings.allowedIntervals.map { String(format: "%.1fs", $0) }
        intervalSegment = NSSegmentedControl(labels: labels, trackingMode: .selectOne, target: self, action: #selector(intervalChanged(_:)))
        intervalSegment.segmentStyle = .rounded
        intervalSegment.translatesAutoresizingMaskIntoConstraints = false

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
            divider(),
            twoColumns,
            divider(),
            footer
        ])
        mainStack.orientation = .vertical
        mainStack.alignment = .leading
        mainStack.spacing = 14
        mainStack.edgeInsets = NSEdgeInsets(top: 20, left: 24, bottom: 20, right: 24)
        mainStack.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 420, height: 460))
        container.addSubview(mainStack)
        NSLayoutConstraint.activate([
            mainStack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            mainStack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            mainStack.topAnchor.constraint(equalTo: container.topAnchor),
            mainStack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            intervalSegment.widthAnchor.constraint(equalTo: mainStack.widthAnchor, constant: -48),
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

    @objc private func menuBarToggled(_ sender: NSButton) {
        guard let raw = sender.identifier?.rawValue, let metric = Metric(rawValue: raw) else { return }
        Settings.shared.toggleMenuBar(metric)
    }

    @objc private func popoverToggled(_ sender: NSButton) {
        guard let raw = sender.identifier?.rawValue, let metric = Metric(rawValue: raw) else { return }
        Settings.shared.togglePopover(metric)
    }

    @objc private func openRepo() {
        if let url = URL(string: "https://github.com/daniel29348679/MacPulse") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - State sync

    private func refresh() {
        let interval = Settings.shared.updateInterval
        if let idx = Settings.allowedIntervals.firstIndex(of: interval) {
            intervalSegment.selectedSegment = idx
        }
        let menuBar = Settings.shared.menuBarMetrics
        let popover = Settings.shared.popoverMetrics
        for (metric, cb) in menuBarCheckboxes {
            cb.state = menuBar.contains(metric) ? .on : .off
        }
        for (metric, cb) in popoverCheckboxes {
            cb.state = popover.contains(metric) ? .on : .off
        }
    }

    func windowWillClose(_ notification: Notification) {
        // Settings 視窗收起時不要結束 app（accessory 模式預設不會，但保險）
    }
}
