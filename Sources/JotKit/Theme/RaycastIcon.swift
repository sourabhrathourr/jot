import AppKit

/// Raycast's icon set, loaded from `Jot.app/Contents/Resources/Icons/<name>.svg`.
/// Those SVGs are extracted at build time from the locally installed Raycast.app
/// (`scripts/extract-raycast-icons.py`) and are not part of this repository; when
/// they're missing, a close SF Symbol is used instead.
enum RaycastIcon {
    private static var cache: [String: NSImage] = [:]

    private static let fallbacks: [String: String] = [
        "command-symbol-20": "command", "docs-stacked-20": "square.on.square", "plus-20": "plus",
        "plus": "plus", "duplicate": "plus.square.on.square", "tack": "pin", "tack-disabled": "pin.slash",
        "docs-stacked": "square.on.square", "arrow-left-circle": "arrow.left.circle", "arrow-right-circle": "arrow.right.circle",
        "find": "text.magnifyingglass", "copy-clipboard": "doc.on.clipboard", "link": "link", "upload": "square.and.arrow.up",
        "arrow-up": "arrow.up", "arrow-down": "arrow.down", "text": "textformat", "app-window": "macwindow",
        "magnifying-glass-one": "1.magnifyingglass", "magnifying-glass-plus": "plus.magnifyingglass",
        "magnifying-glass-minus": "minus.magnifyingglass", "cog": "gearshape", "trash": "trash",
        "brand-markdown": "m.square", "code": "chevron.left.forwardslash.chevron.right", "heading": "textformat.size",
        "x-mark-circle-filled": "xmark.circle.fill", "checkmark": "checkmark", "eye": "eye",
    ]

    /// A template image (tint it with `contentTintColor`) at `size` points.
    static func image(_ name: String, size: CGFloat) -> NSImage? {
        let key = "\(name)@\(size)"
        if let cached = cache[key] { return cached }
        var image: NSImage?
        if let url = Bundle.main.resourceURL?.appendingPathComponent("Icons/\(name).svg"),
           let svg = NSImage(contentsOf: url)?.copy() as? NSImage {
            image = svg
        } else if let symbol = fallbacks[name] {
            image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: size * 0.8, weight: .medium))
        }
        guard let image else { return nil }
        image.size = NSSize(width: size, height: size)
        image.isTemplate = true
        cache[key] = image
        return image
    }
}

/// Raycast's `NativeIconButton` (`.macos__iconButton` + `buttonVariantTertiary` /
/// `buttonVariantGlass`): a round button whose icon is `--fg`, with a `--fg-5`
/// hover and `--fg-10` press, and a 1.05 press scale on macOS 27. When the window
/// isn't key (`[window-blurred]`) the icon drops to 40% opacity.
final class ChromeIconButton: NSView {
    private let imageView = NSImageView()
    private let background = CALayer()
    private var isHovered = false { didSet { refresh() } }
    private var isPressed = false { didSet { refresh() } }
    private var isWindowBlurred = false { didSet { refresh() } }
    private let action: () -> Void
    private let side: CGFloat

    var icon: String { didSet { imageView.image = RaycastIcon.image(icon, size: iconSize) } }
    private let iconSize: CGFloat

    init(icon: String, size: CGFloat, iconSize: CGFloat, tooltip: String, action: @escaping () -> Void) {
        self.icon = icon
        self.side = size
        self.iconSize = iconSize
        self.action = action
        super.init(frame: NSRect(x: 0, y: 0, width: size, height: size))
        toolTip = tooltip
        wantsLayer = true
        layer?.cornerRadius = size / 2
        background.cornerRadius = size / 2
        layer?.addSublayer(background)
        imageView.image = RaycastIcon.image(icon, size: iconSize)
        imageView.imageScaling = .scaleNone
        imageView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(imageView)
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: size),
            heightAnchor.constraint(equalToConstant: size),
            imageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        setAccessibilityRole(.button)
        setAccessibilityLabel(tooltip)
        refresh()
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        background.frame = bounds
        layer?.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        layer?.position = CGPoint(x: frame.midX, y: frame.midY)
    }

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
        isWindowBlurred = !(window?.isKeyWindow ?? false)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }

    override func mouseEntered(with event: NSEvent) { isHovered = true }
    override func mouseExited(with event: NSEvent) { isHovered = false; isPressed = false }
    override func mouseDown(with event: NSEvent) { isPressed = true; setPressScale(true) }

    override func mouseUp(with event: NSEvent) {
        let inside = bounds.contains(convert(event.locationInWindow, from: nil))
        isPressed = false
        setPressScale(false)
        if inside { action() }
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refresh()
    }

    /// `--macos-27-glass-button-active-state-scale: 1.05`, `transform .36s ease-out-back`.
    private func setPressScale(_ pressed: Bool) {
        guard let layer else { return }
        let scale: CGFloat = pressed ? 1.05 : 1
        let animation = CABasicAnimation(keyPath: "transform.scale")
        animation.fromValue = layer.presentation()?.value(forKeyPath: "transform.scale") ?? 1
        animation.toValue = scale
        animation.duration = 0.36
        animation.timingFunction = CAMediaTimingFunction(controlPoints: 0.34, 1.56, 0.64, 1)
        layer.add(animation, forKey: "press")
        layer.setValue(scale, forKeyPath: "transform.scale")
    }

    private func refresh() {
        imageView.contentTintColor = Theme.textPrimary
        imageView.alphaValue = isWindowBlurred ? 0.4 : 1
        effectiveAppearance.performAsCurrentDrawingAppearance {
            let fill: NSColor = isPressed && isHovered ? Theme.fg(0.1) : isHovered ? Theme.fg(0.05) : .clear
            background.backgroundColor = fill.cgColor
        }
    }
}
