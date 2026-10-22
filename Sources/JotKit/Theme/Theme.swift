import AppKit

/// Design tokens lifted from Raycast Notes' shipped CSS (see docs/DESIGN.md).
nonisolated enum Theme {
    /// `--color-brand`. Raycast Notes sets `--theme-accent` to the brand color.
    static let accent = NSColor(srgbRed: 1, green: 0x63 / 255, blue: 0x63 / 255, alpha: 1)

    static func accent(_ alpha: CGFloat) -> NSColor { accent.withAlphaComponent(alpha) }

    /// `--fg`: white in dark appearance, black in light (Raycast Dark / Raycast Light).
    static let fg = dynamic(dark: .white, light: .black)

    /// `rgb(from var(--fg) r g b / alpha)`.
    static func fg(_ alpha: CGFloat) -> NSColor {
        dynamic(dark: NSColor.white.withAlphaComponent(alpha), light: NSColor.black.withAlphaComponent(alpha))
    }

    static let textPrimary = fg
    static let textSecondary = fg(0.6)
    static let textTertiary = fg(0.4)
    static let separator = fg(0.1)
    static let borderSecondary = fg(0.2)

    /// `--red` (Raycast Dark / Raycast Light), used for destructive actions.
    static let red = dynamic(dark: hex(0xFF6363), light: hex(0xB12424))

    /// `--green` (Raycast Dark / Raycast Light), used for success toasts.
    static let green = dynamic(dark: hex(0x59D499), light: hex(0x006B4F))

    static let yellow = dynamic(dark: hex(0xFFC531), light: hex(0xF8A300))
    static let yellow40 = dynamic(dark: hex(0xFFC531, 0.4), light: hex(0xF8A300, 0.4))

    static let selection = accent(0.4)

    static func dynamic(dark: NSColor, light: NSColor) -> NSColor {
        NSColor(name: nil) { $0.isDark ? dark : light }
    }

    static func hex(_ value: UInt32, _ alpha: CGFloat = 1) -> NSColor {
        NSColor(
            srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: alpha
        )
    }
}

nonisolated extension NSAppearance {
    var isDark: Bool { bestMatch(from: [.darkAqua, .aqua]) == .darkAqua }
}

/// Window and chrome metrics (`--space-*`, `--radius-*`, header/footer heights).
nonisolated enum Layout {
    static let windowCornerRadius: CGFloat = 26
    static let headerHeight: CGFloat = 52
    static let footerHeight: CGFloat = 48
    static let trafficLightInset: CGFloat = 58 + 16
    static let editorHorizontalPadding: CGFloat = 24
    static let editorVerticalPadding: CGFloat = 4
    static let chromeFade: TimeInterval = 0.14
    static let defaultSize = NSSize(width: 520, height: 320)
    static let minSize = NSSize(width: 360, height: 180)
}
