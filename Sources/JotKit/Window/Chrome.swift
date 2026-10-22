import AppKit

/// Small factory helpers for the glass chrome.
enum Chrome {
    static func symbol(_ name: String, size: CGFloat = 13, weight: NSFont.Weight = .medium) -> NSImage? {
        NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: size, weight: weight))
    }

    /// A circular Liquid Glass icon button (`--macos-27-glass-button`).
    static func glassButton(_ symbolName: String, size: CGFloat, target: AnyObject, action: Selector, tooltip: String) -> NSButton {
        let button = NSButton(image: symbol(symbolName) ?? NSImage(), target: target, action: action)
        button.bezelStyle = .glass
        button.imagePosition = .imageOnly
        button.toolTip = tooltip
        button.contentTintColor = Theme.textPrimary
        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: size),
            button.heightAnchor.constraint(equalToConstant: size),
        ])
        return button
    }

    /// A flat icon button used inside the format pill.
    static func plainButton(_ symbolName: String, target: AnyObject, action: Selector, tooltip: String) -> FormatButton {
        let image = RaycastIcon.image(symbolName, size: 16) ?? symbol(symbolName, size: 12, weight: .semibold) ?? NSImage()
        let button = FormatButton(image: image, target: target, action: action)
        button.toolTip = tooltip
        return button
    }

    static func label(_ text: String, size: CGFloat, weight: Fonts.Weight = .regular, color: NSColor) -> PassthroughLabel {
        let label = PassthroughLabel(labelWithString: text)
        label.font = Fonts.ui(size: size, weight: weight)
        label.textColor = color
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }

    static func divider(height: CGFloat) -> NSView {
        let view = SeparatorView()
        view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            view.widthAnchor.constraint(equalToConstant: 1),
            view.heightAnchor.constraint(equalToConstant: height),
        ])
        return view
    }
}

/// A borderless 28×28 button with Raycast's hover/active treatment.
final class FormatButton: NSButton {
    var isActive = false { didSet { refresh() } }
    private var isHovered = false { didSet { refresh() } }

    init(image: NSImage, target: AnyObject, action: Selector) {
        super.init(frame: .zero)
        self.image = image
        self.target = target
        self.action = action
        isBordered = false
        imagePosition = .imageOnly
        wantsLayer = true
        layer?.cornerRadius = 8
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(greaterThanOrEqualToConstant: 28),
            heightAnchor.constraint(equalToConstant: 28),
        ])
        refresh()
    }

    required init?(coder: NSCoder) { fatalError() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }

    override func mouseEntered(with event: NSEvent) { isHovered = true }
    override func mouseExited(with event: NSEvent) { isHovered = false }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refresh()
    }

    private func refresh() {
        contentTintColor = isActive ? Theme.textPrimary : Theme.textSecondary
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = (isActive || isHovered) ? Theme.fg(0.1).cgColor : NSColor.clear.cgColor
        }
    }
}

/// A Liquid Glass capsule hosting arbitrary content (`.macos__glass`, `.macos__buttonGroup`
/// padding `--space-4`). Like Raycast's `[macos="27"][window-blurred]` rule, the glass
/// turns subdued while the window isn't key.
final class GlassPill: NSGlassEffectView {
    init(content: NSView, cornerRadius: CGFloat, padding: CGFloat = 4) {
        super.init(frame: .zero)
        GlassRecipe.apply(to: self, cornerRadius: cornerRadius)
        translatesAutoresizingMaskIntoConstraints = false
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        content.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: padding),
            content.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -padding),
            content.topAnchor.constraint(equalTo: container.topAnchor, constant: padding),
            content.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -padding),
        ])
        contentView = container
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        NotificationCenter.default.removeObserver(self)
        guard let window else { return }
        for name in [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification] {
            NotificationCenter.default.addObserver(self, selector: #selector(keyStateChanged), name: name, object: window)
        }
        keyStateChanged()
    }

    @objc private func keyStateChanged() {
        guard responds(to: NSSelectorFromString("set_subduedState:")) else { return }
        setValue((window?.isKeyWindow ?? true) ? 0 : 1, forKey: "_subduedState")
    }
}

/// A 1px line in `--color-border-separator` that follows light/dark changes.
final class SeparatorView: NSView {
    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = Theme.separator.cgColor
        }
    }
}
