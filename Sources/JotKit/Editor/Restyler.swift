import AppKit

/// Derives every visual attribute from the semantic ones. Runs over the whole
/// document after each edit but only writes attributes that actually differ, so
/// TextKit only re-lays out paragraphs whose appearance changed.
struct Restyler {
    var style: EditorStyle

    func restyle(_ storage: NSTextStorage) {
        let paragraphs = storage.paragraphRanges
        guard !paragraphs.isEmpty else { return }
        let infos = paragraphs.map { storage.paragraphInfo(at: $0) }

        var listCounters: [Int: Int] = [:]
        var previousOuterBottom: CGFloat = 0

        storage.beginEditing()
        defer { storage.endEditing() }

        for (i, range) in paragraphs.enumerated() {
            let info = infos[i]
            let previous = i > 0 ? infos[i - 1] : nil
            let next = i + 1 < infos.count ? infos[i + 1] : nil

            var edges: GroupEdges = []
            if previous?.kind != info.kind { edges.insert(.first) }
            if next?.kind != info.kind { edges.insert(.last) }

            var ordinal = 0
            if info.kind.isList {
                listCounters = listCounters.filter { $0.key <= info.indent }
                if info.kind == .ordered {
                    ordinal = (listCounters[info.indent] ?? 0) + 1
                    listCounters[info.indent] = ordinal
                } else {
                    listCounters[info.indent] = 0
                }
            } else {
                listCounters.removeAll()
            }

            let margins = style.margins(info.kind, edges: edges, afterRuleOrStart: previous == nil || previous?.kind == .rule)
            let correction = style.baselineCorrection(info.kind)
            let paragraphStyle = makeParagraphStyle(
                info,
                spacingBefore: max(previousOuterBottom, margins.outerTop) + margins.innerTop - correction,
                spacingAfter: margins.innerBottom + correction
            )
            previousOuterBottom = margins.outerBottom

            let paragraphAttributes: [NSAttributedString.Key: Any] = info.attributes.merging([
                .jotOrdinal: ordinal,
                .jotEdges: edges.rawValue,
                .paragraphStyle: paragraphStyle,
            ]) { $1 }

            styleRuns(storage, in: range, info: info, paragraphAttributes: paragraphAttributes)
        }
    }

    /// The full attribute set a newly typed character should get.
    func typingAttributes(info: ParagraphInfo, marks: Marks, href: String?, paragraphStyle: NSParagraphStyle?) -> [NSAttributedString.Key: Any] {
        var attributes = visualAttributes(info: info, marks: marks, href: href)
        attributes.merge(info.attributes) { $1 }
        attributes[.jotMarks] = marks.rawValue
        if let href { attributes[.jotHref] = href }
        if let paragraphStyle { attributes[.paragraphStyle] = paragraphStyle }
        return attributes
    }

    private struct Segment {
        var range: NSRange
        var marks: Marks
        var href: String?
    }

    private func styleRuns(_ storage: NSTextStorage, in range: NSRange, info: ParagraphInfo, paragraphAttributes: [NSAttributedString.Key: Any]) {
        let string = storage.string as NSString
        let endsWithNewline = range.length > 0 && string.character(at: NSMaxRange(range) - 1) == 0x0A
        let content = NSRange(location: range.location, length: range.length - (endsWithNewline ? 1 : 0))

        // Split the content into runs of identical semantics.
        var segments: [Segment] = []
        storage.enumerateAttributes(in: content) { attributes, runRange, _ in
            let marks = info.kind == .code ? [] : Marks(rawValue: attributes[.jotMarks] as? Int ?? 0)
            let href = attributes[.jotHref] as? String
            if let last = segments.last, last.marks == marks, last.href == href {
                segments[segments.count - 1].range.length += runRange.length
            } else {
                segments.append(Segment(range: runRange, marks: marks, href: href))
            }
        }

        // Inline code pills need breathing room on both sides (CSS `padding: 0 .4em`):
        // kern the character before a code run and the last character of it.
        let codePad = (style.fontSize(info.kind) * 0.835 * 0.4).rounded()
        for (i, segment) in segments.enumerated() {
            let nextIsCode = i + 1 < segments.count && segments[i + 1].marks.contains(.code)
            let padsEnd = segment.marks.contains(.code) || nextIsCode
            var desired = visualAttributes(info: info, marks: segment.marks, href: segment.href)
            desired.merge(paragraphAttributes) { $1 }
            desired[.jotMarks] = segment.marks.rawValue
            if let href = segment.href { desired[.jotHref] = href }
            // An image block's one character is its attachment; restyling must keep it.
            if info.kind == .image, let attachment = storage.attribute(.attachment, at: segment.range.location, effectiveRange: nil) {
                desired[.attachment] = attachment
            }

            if padsEnd {
                let body = NSRange(location: segment.range.location, length: segment.range.length - 1)
                if body.length > 0 { apply(desired, to: storage, range: body) }
                var last = desired
                last[.kern] = codePad
                apply(last, to: storage, range: NSRange(location: NSMaxRange(segment.range) - 1, length: 1))
            } else {
                apply(desired, to: storage, range: segment.range)
            }
        }

        // The newline anchors the block and never carries inline marks, so marks can't leak.
        if endsWithNewline {
            var desired = visualAttributes(info: info, marks: [], href: nil)
            desired.merge(paragraphAttributes) { $1 }
            desired[.jotMarks] = 0
            apply(desired, to: storage, range: NSRange(location: NSMaxRange(range) - 1, length: 1))
        }
    }

    private func apply(_ desired: [NSAttributedString.Key: Any], to storage: NSTextStorage, range: NSRange) {
        var effective = NSRange()
        let existing = storage.attributes(at: range.location, longestEffectiveRange: &effective, in: range)
        if NSEqualRanges(effective, range), NSDictionary(dictionary: existing).isEqual(to: desired) { return }
        storage.setAttributes(desired, range: range)
    }

    private func visualAttributes(info: ParagraphInfo, marks: Marks, href: String?) -> [NSAttributedString.Key: Any] {
        var attributes: [NSAttributedString.Key: Any] = [.font: style.font(info.kind, marks: marks)]

        let checked = info.kind == .task && info.checked
        if href != nil {
            attributes[.foregroundColor] = checked ? EditorStyle.linkChecked : EditorStyle.link
            attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
            attributes[.underlineColor] = EditorStyle.linkUnderline
        } else if marks.contains(.code) {
            attributes[.foregroundColor] = checked ? EditorStyle.inlineCodeTextChecked : EditorStyle.inlineCodeText
        } else if info.kind == .code {
            attributes[.foregroundColor] = EditorStyle.codeBlockText
        } else {
            attributes[.foregroundColor] = checked ? EditorStyle.checkedText : EditorStyle.text
        }
        if marks.contains(.underline), href == nil { attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue }
        if marks.contains(.strike) { attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
        return attributes
    }

    func makeParagraphStyle(_ info: ParagraphInfo, spacingBefore: CGFloat = 0, spacingAfter: CGFloat = 0) -> NSParagraphStyle {
        let paragraph = NSMutableParagraphStyle()
        let lineHeight = style.lineHeight(info.kind)
        if lineHeight > 0 {
            paragraph.minimumLineHeight = lineHeight
            paragraph.maximumLineHeight = lineHeight
        }
        paragraph.paragraphSpacingBefore = spacingBefore
        paragraph.paragraphSpacing = spacingAfter
        let indent = style.textIndent(info)
        paragraph.firstLineHeadIndent = indent
        paragraph.headIndent = indent
        if info.kind == .code {
            paragraph.tailIndent = -style.px(12)
            paragraph.lineBreakMode = .byCharWrapping
            paragraph.defaultTabInterval = style.fontSize(.code) * 0.6 * 2
        }
        return paragraph
    }
}
