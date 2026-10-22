import AppKit

/// Raycast 2.8.2's window material, recovered from `RaycastMacOSUI/WindowContainerViewController.swift`
/// and verified pixel-for-pixel against a live Raycast Notes window over a fixed test pattern
/// (RMSE 0.03/255, identical blur profile):
///
///   NSVisualEffectView   material .popover, blendingMode .behindWindow, state .active
///   CAGradientLayer      --color-window-bg → --color-window-bg-secondary, both theme bg @ 40%
///                        (Raycast Dark: black; Raycast Light: white), locations [0, 1], top → bottom
///   NSThemeFrame         `_cornerRadius` swizzled to 26 so the frame border/shadow hug the material
///   NSWindow             `_setForceMainAppearance:` YES, so it never dims when inactive
///
/// Liquid Glass (`NSGlassEffectView`) is only used for controls (buttons, pills, find bar),
/// with `raycastPopoverTint` for floating menus.
enum GlassRecipe {
    /// `raycastPopoverTint`: dark → black @ 45%, light → white @ 27%.
    static let popoverTint = NSColor(name: "raycastPopoverTint") { appearance in
        appearance.isDark ? NSColor.black.withAlphaComponent(0.45) : NSColor.white.withAlphaComponent(0.27)
    }

    /// Liquid Glass for controls, as `NSGlassEffectView+Private` configures it.
    static func apply(to glass: NSGlassEffectView, tint: NSColor? = nil, cornerRadius: CGFloat) {
        glass.style = .regular
        glass.cornerRadius = cornerRadius
        glass.tintColor = tint
        if glass.responds(to: NSSelectorFromString("set_adaptiveAppearance:")) {
            glass.setValue(1, forKey: "_adaptiveAppearance")
        }
    }

    static func apply(to window: NSWindow) {
        let selector = NSSelectorFromString("_setForceMainAppearance:")
        guard window.responds(to: selector) else { return }
        typealias Setter = @convention(c) (NSWindow, Selector, Bool) -> Void
        unsafeBitCast(window.method(for: selector), to: Setter.self)(window, selector, true)
    }
}

/// The notes window background (see `GlassRecipe`).
final class WindowBackdropView: NSVisualEffectView {
    private let gradient = CAGradientLayer()

    var contentView: NSView? {
        didSet {
            oldValue?.removeFromSuperview()
            guard let contentView else { return }
            contentView.frame = bounds
            contentView.autoresizingMask = [.width, .height]
            addSubview(contentView)
        }
    }

    init(cornerRadius: CGFloat) {
        super.init(frame: .zero)
        material = .popover
        blendingMode = .behindWindow
        state = .active
        autoresizingMask = [.width, .height]
        wantsLayer = true
        maskImage = Self.mask(cornerRadius: cornerRadius)
        gradient.locations = [0, 1]
        gradient.startPoint = CGPoint(x: 0.5, y: 0)
        gradient.endPoint = CGPoint(x: 0.5, y: 1)
        layer?.addSublayer(gradient)
        updateGradient()
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        gradient.frame = bounds
        CATransaction.commit()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateGradient()
    }

    /// `--color-window-bg` / `--color-window-bg-secondary`: the theme background at 40%.
    private func updateGradient() {
        let background: NSColor = effectiveAppearance.isDark ? .black : .white
        let color = background.withAlphaComponent(0.4).cgColor
        gradient.colors = [color, color]
    }

    private static func mask(cornerRadius: CGFloat) -> NSImage {
        let size = NSSize(width: cornerRadius * 2 + 1, height: cornerRadius * 2 + 1)
        let image = NSImage(size: size, flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: cornerRadius, left: cornerRadius, bottom: cornerRadius, right: cornerRadius)
        image.resizingMode = .stretch
        return image
    }
}
