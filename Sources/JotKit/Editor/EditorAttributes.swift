import AppKit

/// Semantic attributes stored in the text. Presentation (fonts, colors, paragraph
/// styles) is derived from these by `Restyler`; nothing else is persisted.
nonisolated extension NSAttributedString.Key {
    /// `BlockKind.rawValue`. The paragraph's terminating newline is the source of truth.
    static let jotBlock = NSAttributedString.Key("jot.block")
    /// List nesting depth (Int).
    static let jotIndent = NSAttributedString.Key("jot.indent")
    /// Task checked state (Bool).
    static let jotChecked = NSAttributedString.Key("jot.checked")
    /// Code block language (String), the same on every line of the block.
    static let jotLanguage = NSAttributedString.Key("jot.language")
    /// `Marks.rawValue` (Int).
    static let jotMarks = NSAttributedString.Key("jot.marks")
    /// Link target (String). We don't use `.link` so NSTextView doesn't hijack clicks.
    static let jotHref = NSAttributedString.Key("jot.href")

    // Derived by the restyler, read by the layout fragment.
    /// Ordered-list number (Int).
    static let jotOrdinal = NSAttributedString.Key("jot.ordinal")
    /// `GroupEdges.rawValue` for code/quote groups (Int).
    static let jotEdges = NSAttributedString.Key("jot.edges")
}

nonisolated struct GroupEdges: OptionSet {
    let rawValue: Int
    static let first = GroupEdges(rawValue: 1)
    static let last = GroupEdges(rawValue: 2)
}

/// The block-level state of one paragraph.
nonisolated struct ParagraphInfo: Equatable {
    var kind: BlockKind = .paragraph
    var indent: Int = 0
    var checked: Bool = false
    var language: String?

    init(kind: BlockKind = .paragraph, indent: Int = 0, checked: Bool = false, language: String? = nil) {
        self.kind = kind
        self.indent = indent
        self.checked = checked
        self.language = kind == .code ? language : nil
    }

    init(attributes: [NSAttributedString.Key: Any]) {
        kind = (attributes[.jotBlock] as? String).flatMap(BlockKind.init(rawValue:)) ?? .paragraph
        indent = attributes[.jotIndent] as? Int ?? 0
        checked = attributes[.jotChecked] as? Bool ?? false
        language = kind == .code ? (attributes[.jotLanguage] as? String).flatMap { $0.isEmpty ? nil : $0 } : nil
    }

    /// `jotLanguage` is always present so that applying the attributes clears a stale one.
    var attributes: [NSAttributedString.Key: Any] {
        [.jotBlock: kind.rawValue, .jotIndent: indent, .jotChecked: checked, .jotLanguage: language ?? ""]
    }
}

nonisolated extension NSAttributedString {
    /// The block state of the paragraph containing `range`, read from its anchor
    /// (the terminating newline, or the first character when there is none).
    func paragraphInfo(at paragraphRange: NSRange) -> ParagraphInfo {
        guard length > 0, paragraphRange.location < length else { return ParagraphInfo() }
        let string = self.string as NSString
        let last = NSMaxRange(paragraphRange) - 1
        let anchor = last >= paragraphRange.location && last < length && string.character(at: last) == 0x0A
            ? last
            : paragraphRange.location
        return ParagraphInfo(attributes: attributes(at: anchor, effectiveRange: nil))
    }

    func marks(at index: Int) -> Marks {
        guard index >= 0, index < length else { return [] }
        return Marks(rawValue: attribute(.jotMarks, at: index, effectiveRange: nil) as? Int ?? 0)
    }

    /// Ranges of every paragraph (each includes its terminating newline when present).
    var paragraphRanges: [NSRange] {
        let string = self.string as NSString
        var ranges: [NSRange] = []
        var location = 0
        while location < string.length {
            let range = string.paragraphRange(for: NSRange(location: location, length: 0))
            ranges.append(range)
            location = NSMaxRange(range)
        }
        return ranges
    }
}
