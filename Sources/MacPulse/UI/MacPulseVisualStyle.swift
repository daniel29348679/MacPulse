import AppKit

enum MacPulseVisualStyle {
    static let popoverWidth: CGFloat = 324
    static let cardCornerRadius: CGFloat = 16
    static let cardInsets = NSEdgeInsets(top: 13, left: 14, bottom: 13, right: 14)

    static func accentColor(for metric: Metric) -> NSColor {
        switch metric {
        case .cpu:         return .systemBlue
        case .gpu:         return .systemTeal
        case .memory:      return .systemPurple
        case .network:     return .systemGreen
        case .disk:        return .systemOrange
        case .temperature: return .systemPink
        case .power:       return .systemYellow
        }
    }

    static func card(around content: NSView,
                     insets: NSEdgeInsets = cardInsets) -> NSView {
        let card = MaterialCardView(cornerRadius: cardCornerRadius)
        content.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: insets.left),
            content.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -insets.right),
            content.topAnchor.constraint(equalTo: card.topAnchor, constant: insets.top),
            content.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -insets.bottom)
        ])
        return card
    }

    static func symbolBadge(_ symbolName: String,
                            color: NSColor,
                            accessibilityDescription: String? = nil,
                            size: CGFloat = 30) -> NSView {
        SymbolBadgeView(symbolName: symbolName,
                        color: color,
                        accessibilityDescription: accessibilityDescription,
                        size: size)
    }

    static func configureGlassButton(_ button: NSButton,
                                     primary: Bool = false,
                                     controlSize: NSControl.ControlSize = .regular) {
        button.isBordered = true
        button.controlSize = controlSize
        if #available(macOS 26.0, *) {
            button.bezelStyle = .glass
            button.tintProminence = primary ? .primary : .secondary
        } else {
            button.bezelStyle = button.title.isEmpty ? .circular : .rounded
        }
    }
}

private final class MaterialCardView: NSVisualEffectView {
    private let radius: CGFloat

    init(cornerRadius: CGFloat) {
        radius = cornerRadius
        super.init(frame: .zero)
        material = .contentBackground
        blendingMode = .withinWindow
        state = .followsWindowActiveState
        wantsLayer = true
        layer?.cornerRadius = cornerRadius
        layer?.masksToBounds = true
        if #available(macOS 10.15, *) {
            layer?.cornerCurve = .continuous
        }
        updateBorderColor()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        layer?.cornerRadius = radius
        updateBorderColor()
    }

    private func updateBorderColor() {
        layer?.borderWidth = 0.5
        layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.22).cgColor
    }
}

private final class SymbolBadgeView: NSView {
    private let badgeColor: NSColor

    init(symbolName: String,
         color: NSColor,
         accessibilityDescription: String?,
         size: CGFloat) {
        badgeColor = color
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = size / 2
        if #available(macOS 10.15, *) {
            layer?.cornerCurve = .continuous
        }

        let imageView = NSImageView()
        if let image = NSImage(systemSymbolName: symbolName,
                               accessibilityDescription: accessibilityDescription) {
            imageView.image = image.withSymbolConfiguration(.init(pointSize: size * 0.47,
                                                                   weight: .semibold))
        }
        imageView.contentTintColor = color
        imageView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(imageView)

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: size),
            heightAnchor.constraint(equalToConstant: size),
            imageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
        updateBackgroundColor()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateBackgroundColor()
    }

    private func updateBackgroundColor() {
        layer?.backgroundColor = badgeColor.withAlphaComponent(0.14).cgColor
        layer?.borderWidth = 0.5
        layer?.borderColor = badgeColor.withAlphaComponent(0.28).cgColor
    }
}
