import AppKit

/// Raycast Notes' editor CSS, as numbers. Everything scales with `zoom` (`--spx`).
nonisolated struct EditorStyle {
    var zoom: CGFloat = 1

    /// `round(calc(n * var(--spx)), 1px)`
    func px(_ value: CGFloat) -> CGFloat { (value * zoom).rounded() }

    func fontSize(_ kind: BlockKind) -> CGFloat {
        let base: CGFloat = switch kind {
        case .heading1: 22
        case .heading2: 18
        case .heading3: 16
        case .code: 13
        // The attachment sets an image block's height; a tiny font keeps the line from adding any.
        case .image: 1
        default: 14
        }
        return base * zoom
    }

    func lineHeight(_ kind: BlockKind) -> CGFloat {
        switch kind {
        case .heading1, .heading2, .heading3: fontSize(kind) * 1.25
        case .code: fontSize(kind) * 1.5
        case .rule: 2 * zoom
        case .image: 0
        default: fontSize(kind) * 1.45
        }
    }

    func baseFont(_ kind: BlockKind) -> NSFont { font(kind, marks: []) }

    /// TextKit 2 sits the baseline `round(descender)` above the bottom of a fixed-height
    /// line; CSS centres the glyphs (half-leading). This is how far TextKit's text sits
    /// below where WebKit draws it, so each block is laid out this much higher.
    func baselineCorrection(_ kind: BlockKind) -> CGFloat {
        guard kind != .rule, kind != .image else { return 0 }
        let font = baseFont(kind)
        let lineHeight = lineHeight(kind)
        let textKitBaseline = lineHeight - (-font.descender).rounded()
        let cssBaseline = (lineHeight - (font.ascender - font.descender)) / 2 + font.ascender
        return textKitBaseline - cssBaseline
    }

    func font(_ kind: BlockKind, marks: Marks) -> NSFont {
        let key = FontKey(kind: kind, marks: marks.intersection([.bold, .italic, .code]), zoom: zoom)
        if let cached = Self.fontCache[key] { return cached }
        let size = fontSize(kind)
        let italic = marks.contains(.italic)
        let bold = marks.contains(.bold)
        let font: NSFont
        if kind == .code {
            font = Fonts.mono(size: size, bold: bold, italic: italic)
        } else if marks.contains(.code) {
            font = Fonts.mono(size: size * 0.835, bold: bold, italic: italic)
        } else {
            let weight: Fonts.Weight = switch kind {
            case .heading1, .heading2: .semibold
            case .heading3: bold ? .semibold : .medium
            default: bold ? .semibold : .regular
            }
            font = Fonts.inter(size: size, weight: weight, italic: italic)
        }
        Self.fontCache[key] = font
        return font
    }

    /// Text starts this far from the content edge.
    func textIndent(_ info: ParagraphInfo) -> CGFloat {
        switch info.kind {
        case .bullet, .ordered, .task: px(22) * CGFloat(info.indent + 1)
        case .quote: px(12)
        case .code: px(12)
        default: 0
        }
    }

    struct Margins {
        var outerTop: CGFloat = 0
        var outerBottom: CGFloat = 0
        var innerTop: CGFloat = 0
        var innerBottom: CGFloat = 0
    }

    /// CSS margins for a paragraph. Outer margins collapse with the neighbour's, inner ones don't.
    func margins(_ kind: BlockKind, edges: GroupEdges, afterRuleOrStart: Bool) -> Margins {
        switch kind {
        case .paragraph, .bullet, .ordered, .task:
            return Margins(outerTop: px(8))
        case .heading1:
            return Margins(outerTop: afterRuleOrStart ? px(8) : px(30), outerBottom: px(8))
        case .heading2:
            return Margins(outerTop: afterRuleOrStart ? px(6) : px(18), outerBottom: px(6))
        case .heading3:
            return Margins(outerTop: afterRuleOrStart ? px(4) : px(18), outerBottom: px(4))
        case .quote:
            return Margins(outerTop: edges.contains(.first) ? px(8) : 0)
        case .code:
            return Margins(
                outerTop: edges.contains(.first) ? px(12) : 0,
                outerBottom: edges.contains(.last) ? px(12) : 0,
                innerTop: edges.contains(.first) ? px(8) : 0,
                innerBottom: edges.contains(.last) ? px(12) : 0
            )
        case .rule:
            return Margins(outerTop: px(16), outerBottom: px(16))
        case .image:
            // `.imageBlock { margin: 12px 0 }`, and 24px between two images.
            return Margins(outerTop: edges.contains(.first) ? px(12) : px(24), outerBottom: px(12))
        }
    }

    // MARK: Colors (static so attribute diffs compare equal)

    static let text = Theme.fg
    static let codeBlockText = Theme.fg(0.8)
    static let inlineCodeText = Theme.fg(0.6)
    static let inlineCodeTextChecked = Theme.fg(0.3)
    static let checkedText = Theme.fg(0.7)
    static let link = Theme.accent
    static let linkChecked = Theme.accent(0.7)
    static let linkUnderline = Theme.accent(0.55)
    static let inlineCodeBackground = Theme.fg(0.1)
    static let inlineCodeBackgroundChecked = Theme.fg(0.05)
    static let codeBlockBackground = Theme.fg(0.05)

    private struct FontKey: Hashable {
        var kind: BlockKind
        var marks: Marks
        var zoom: CGFloat
    }

    nonisolated(unsafe) private static var fontCache: [FontKey: NSFont] = [:]
}
