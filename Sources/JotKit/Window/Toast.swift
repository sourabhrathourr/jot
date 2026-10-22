import AppKit

/// Raycast's in-window toast (`InWindowToasts` + `Toast` in `window-shell-hosts`): a Liquid
/// Glass capsule 40pt below the window top with a status dot and a tinted glow from its top
/// edge. It stays for 3s (paused while hovered) and fades out over 200ms.
final class ToastHost: NSView {
    enum Variant {
        case success, failure

        var color: NSColor {
            switch self {
            case .success: Theme.green
            case .failure: Theme.red
            }
        }
    }

    /// `.in-window-toasts__wrapper`: `top: 40px`, `padding-inline: var(--space-56)`.
    static let top: CGFloat = 40
    static let sideInset: CGFloat = 56

    private var toast: ToastView?
    private var dismissTimer: Timer?
    private var topConstraint: NSLayoutConstraint?

    override init(frame: NSRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
    }

    required init?(coder: NSCoder) { fatalError() }

    /// Only the toast itself takes the mouse (`pointer-events: none` on the wrapper).
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let toast, let hit = super.hitTest(point), hit.isDescendant(of: toast) else { return nil }
        return hit
    }

    func show(_ title: String, message: String? = nil, variant: Variant = .success) {
        // A new toast replaces the current one in place; only a fresh one animates in.
        if let toast {
            toast.layer?.removeAllAnimations()
            toast.alphaValue = 1
            toast.configure(title: title, message: message, variant: variant)
            scheduleDismiss()
            return
        }

        let toast = ToastView()
        toast.configure(title: title, message: message, variant: variant)
        toast.onHoverChange = { [weak self] hovered in
            if hovered { self?.cancelDismiss() } else { self?.scheduleDismiss() }
        }
        addSubview(toast)
        let top = toast.topAnchor.constraint(equalTo: topAnchor, constant: Self.top - 5)
        NSLayoutConstraint.activate([
            top,
            toast.centerXAnchor.constraint(equalTo: centerXAnchor),
            toast.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: Self.sideInset),
            toast.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -Self.sideInset),
            toast.widthAnchor.constraint(lessThanOrEqualToConstant: 600),
        ])
        self.toast = toast
        topConstraint = top
        layoutSubtreeIfNeeded()

        // `in-window-toasts__open`: .3s ease-out, opacity 0 → 1, translateY(-5px) → 0.
        toast.alphaValue = 0
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            context.allowsImplicitAnimation = true
            toast.animator().alphaValue = 1
            top.animator().constant = Self.top
            layoutSubtreeIfNeeded()
        }
        scheduleDismiss()
    }

    func dismiss() {
        cancelDismiss()
        toast?.removeFromSuperview()
        toast = nil
        topConstraint = nil
    }

    private func scheduleDismiss() {
        cancelDismiss()
        dismissTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.fadeOut() }
        }
    }

    private func cancelDismiss() {
        dismissTimer?.invalidate()
        dismissTimer = nil
        if let toast, toast.alphaValue < 1 {
            toast.layer?.removeAllAnimations()
            toast.alphaValue = 1
        }
    }

    /// Fades only while the window is active; otherwise it just goes away.
    private func fadeOut() {
        dismissTimer = nil
        guard let toast else { return }
        guard window?.isKeyWindow == true else { return dismiss() }
        NSAnimationContext.runAnimationGroup { context in
            // `element.animate([{ opacity: 1 }, { opacity: 0 }], { duration: 200 })`: linear.
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .linear)
            toast.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.toast === toast, toast.alphaValue == 0 else { return }
                self.dismiss()
            }
        }
    }
}

/// `.toast__root`: glass at radius 12 (`yt(3)` on macOS), padding 8 / 16 / 8 / 8 with an
/// indicator, gap 6, the title in the 13px `text` style.
private final class ToastView: NSView {
    var onHoverChange: ((Bool) -> Void)?

    private let glass = NSGlassEffectView()
    private let tint = ToastTintView()
    private let indicator = ToastIndicator()
    private let titleLabel = PassthroughLabel(labelWithString: "")
    /// `.toast__message`: `small-text`, secondary, truncating, 2pt under the title.
    private let messageLabel = PassthroughLabel(labelWithString: "")
    private var titleBaseline: NSLayoutConstraint!
    private var singleLine: [NSLayoutConstraint] = []
    private var twoLines: [NSLayoutConstraint] = []

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        GlassRecipe.apply(to: glass, cornerRadius: 12)
        glass.translatesAutoresizingMaskIntoConstraints = false
        addSubview(glass)

        let content = NSView()
        content.wantsLayer = true
        content.layer?.cornerRadius = 12
        content.layer?.masksToBounds = true
        content.translatesAutoresizingMaskIntoConstraints = false
        glass.contentView = content

        titleLabel.textColor = Theme.textPrimary
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.font = Fonts.ui(size: 13)
        messageLabel.font = Fonts.ui(size: 11)
        messageLabel.textColor = Theme.textSecondary
        messageLabel.lineBreakMode = .byTruncatingTail
        messageLabel.isHidden = true
        for view in [tint, indicator, titleLabel, messageLabel] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(view)
        }

        NSLayoutConstraint.activate([
            glass.topAnchor.constraint(equalTo: topAnchor),
            glass.bottomAnchor.constraint(equalTo: bottomAnchor),
            glass.leadingAnchor.constraint(equalTo: leadingAnchor),
            glass.trailingAnchor.constraint(equalTo: trailingAnchor),
            tint.topAnchor.constraint(equalTo: content.topAnchor),
            tint.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            tint.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            tint.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            indicator.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 8),
            indicator.centerYAnchor.constraint(equalTo: content.centerYAnchor),
            indicator.widthAnchor.constraint(equalToConstant: 16),
            indicator.heightAnchor.constraint(equalToConstant: 16),
            titleLabel.leadingAnchor.constraint(equalTo: indicator.trailingAnchor, constant: 6),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: content.trailingAnchor, constant: -16),
            messageLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            messageLabel.trailingAnchor.constraint(lessThanOrEqualTo: content.trailingAnchor, constant: -16),
        ])
        titleBaseline = titleLabel.firstBaselineAnchor.constraint(equalTo: content.topAnchor)
        singleLine = [titleBaseline, content.heightAnchor.constraint(equalToConstant: 32)]
        // With a message the text column sits 1pt higher (`.toast__details:has(.toast__message) { top: -1px }`).
        twoLines = [
            titleLabel.topAnchor.constraint(equalTo: content.topAnchor, constant: 7),
            messageLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
            content.bottomAnchor.constraint(equalTo: messageLabel.bottomAnchor, constant: 9),
        ]
        NSLayoutConstraint.activate(singleLine)
        applyFont()
    }

    required init?(coder: NSCoder) { fatalError() }

    private var title = ""

    func configure(title: String, message: String? = nil, variant: ToastHost.Variant) {
        self.title = title
        setTitle(title)
        messageLabel.stringValue = message ?? ""
        messageLabel.isHidden = message == nil
        NSLayoutConstraint.deactivate(message == nil ? twoLines : singleLine)
        NSLayoutConstraint.activate(message == nil ? singleLine : twoLines)
        tint.color = variant.color
        indicator.color = variant.color
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        applyFont()
    }

    /// `.text__size-13` is 13px, minus 0.1px on 1x displays. The line box (ascender +
    /// descender) is centred in the 16pt row like CSS `align-items: center`, which puts the
    /// baseline at 8 + (16 − line height) / 2 + ascender rather than where AppKit centres a label.
    private func applyFont() {
        let font = Fonts.ui(size: (window?.backingScaleFactor ?? 2) < 2 ? 12.9 : 13)
        titleLabel.font = font
        setTitle(title)
        let lineHeight = font.ascender - font.descender
        titleBaseline.constant = 8 + (16 - lineHeight) / 2 + font.ascender
    }

    /// WebKit rounds the width of a space to whole CSS pixels (`Font::adjustedSpaceWidth`);
    /// the other glyphs keep their exact advances. Inter's space at 12.9px is 3.63 → 4, which
    /// is why "Zoomed to 105%" sits 1px wider in Raycast. Kerning each space by its rounding
    /// error reproduces that spacing.
    private func setTitle(_ title: String) {
        guard let font = titleLabel.font else { return }
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        let text = NSMutableAttributedString(string: title, attributes: [
            .font: font,
            .foregroundColor: Theme.textPrimary,
            .paragraphStyle: paragraph,
        ])
        let line = CTLineCreateWithAttributedString(text)
        let characters = title as NSString
        for run in CTLineGetGlyphRuns(line) as? [CTRun] ?? [] {
            let count = CTRunGetGlyphCount(run)
            var advances = [CGSize](repeating: .zero, count: count)
            var indices = [CFIndex](repeating: 0, count: count)
            CTRunGetAdvances(run, CFRange(location: 0, length: count), &advances)
            CTRunGetStringIndices(run, CFRange(location: 0, length: count), &indices)
            for (advance, index) in zip(advances, indices) where characters.character(at: index) == 0x20 || characters.character(at: index) == 0xA0 {
                let delta = advance.width.rounded() - advance.width
                // A kern of exactly 0 would switch the font's own kerning off for that pair.
                guard abs(delta) > 0.001 else { continue }
                text.addAttribute(.kern, value: delta, range: NSRange(location: index, length: 1))
            }
        }
        titleLabel.attributedStringValue = text
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }

    override func mouseEntered(with event: NSEvent) { onHoverChange?(true) }
    override func mouseExited(with event: NSEvent) { onHoverChange?(false) }

    // The toast swallows clicks rather than letting them drag the window or reach the editor.
    override func mouseDown(with event: NSEvent) {}
}

/// `.toast__variantBackground`: two radial glows of the variant colour at 26%, centred just
/// above the top edge: `radial-gradient(45% 30% at 50% -10%, …)` over
/// `radial-gradient(100% 90% at 50% -15%, …)`.
private final class ToastTintView: NSView {
    var color: NSColor = Theme.green { didSet { needsDisplay = true } }

    private let glows = [CAGradientLayer(), CAGradientLayer()]
    /// (center y from the top, x radius, y radius) as fractions of the toast.
    private let shapes: [(CGFloat, CGFloat, CGFloat)] = [(-0.15, 1, 0.9), (-0.1, 0.45, 0.3)]

    override var wantsUpdateLayer: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        glows.forEach {
            $0.type = .radial
            layer?.addSublayer($0)
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        updateLayer()
    }

    override func updateLayer() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        effectiveAppearance.performAsCurrentDrawingAppearance {
            let base = color.withAlphaComponent(0.26).cgColor
            let clear = color.withAlphaComponent(0).cgColor
            for (glow, shape) in zip(glows, shapes) {
                glow.frame = bounds
                glow.colors = [base, clear]
                // Unit space runs bottom-up unless the layer's contents are flipped.
                let flipped = glow.contentsAreFlipped()
                let centerY = flipped ? shape.0 : 1 - shape.0
                glow.startPoint = CGPoint(x: 0.5, y: centerY)
                glow.endPoint = CGPoint(x: 0.5 + shape.1, y: centerY + (flipped ? shape.2 : -shape.2))
            }
        }
        CATransaction.commit()
    }
}

/// `.activity-indicator` in a resolved state: a 5pt dot in the variant colour with a
/// `0 0 12px 8px` glow of the same colour at 20%, centred in a 16pt box.
private final class ToastIndicator: NSView {
    var color: NSColor = Theme.green { didSet { needsDisplay = true } }

    private let dot = CALayer()

    override var wantsUpdateLayer: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = false
        dot.cornerRadius = 2.5
        // A CSS spread has no CALayer equivalent: grow the shadow path by the spread instead.
        let spread: CGFloat = 8
        dot.shadowPath = CGPath(ellipseIn: CGRect(x: -spread, y: -spread, width: 5 + spread * 2, height: 5 + spread * 2), transform: nil)
        dot.shadowOffset = .zero
        dot.shadowRadius = 6
        dot.shadowOpacity = 1
        layer?.addSublayer(dot)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        updateLayer()
    }

    override func updateLayer() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let scale = window?.backingScaleFactor ?? 2
        // Centred like CSS `place-items: center`: 5.5pt rounds to 6 from the top-left.
        let inset = ((bounds.width - 5) / 2 * scale).rounded() / scale
        dot.frame = CGRect(x: inset, y: bounds.height - 5 - inset, width: 5, height: 5)
        effectiveAppearance.performAsCurrentDrawingAppearance {
            dot.backgroundColor = color.cgColor
            dot.shadowColor = color.withAlphaComponent(0.2).cgColor
        }
        CATransaction.commit()
    }
}
