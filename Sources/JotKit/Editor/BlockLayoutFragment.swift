import AppKit

/// Draws the decorations Raycast's CSS draws with pseudo-elements: list markers,
/// task checkboxes, the blockquote bar, code-block backgrounds, rules, and
/// inline-code pills.
nonisolated final class BlockLayoutFragment: NSTextLayoutFragment {
    var style = EditorStyle()
    /// Dynamic colors resolve against this while drawing.
    var appearance: NSAppearance?
    /// Where image blocks' files are.
    var attachments: AttachmentStore?

    private var paragraphAttributes: [NSAttributedString.Key: Any] {
        guard let paragraph = textElement as? NSTextParagraph, paragraph.attributedString.length > 0 else { return [:] }
        let string = paragraph.attributedString
        let anchor = (string.string as NSString).character(at: string.length - 1) == 0x0A ? string.length - 1 : 0
        return string.attributes(at: anchor, effectiveRange: nil)
    }

    private var info: ParagraphInfo { ParagraphInfo(attributes: paragraphAttributes) }

    private var containerWidth: CGFloat {
        textLayoutManager?.textContainer?.size.width ?? layoutFragmentFrame.width
    }

    /// TextKit 2 may offset the fragment by the paragraph indent; this is the
    /// container's left edge in fragment coordinates.
    private var containerMinX: CGFloat { -layoutFragmentFrame.minX }

    override var renderingSurfaceBounds: CGRect {
        let base = super.renderingSurfaceBounds
        let wide = CGRect(x: containerMinX - 48, y: base.minY - 16, width: containerWidth + 96, height: base.height + 32)
        return base.union(wide)
    }

    override func draw(at point: CGPoint, in context: CGContext) {
        if let appearance {
            appearance.performAsCurrentDrawingAppearance { drawDecorated(at: point, in: context) }
        } else {
            drawDecorated(at: point, in: context)
        }
    }

    private func drawDecorated(at point: CGPoint, in context: CGContext) {
        let info = self.info
        let edges = GroupEdges(rawValue: paragraphAttributes[.jotEdges] as? Int ?? 0)
        let lines = textLineFragments

        context.saveGState()
        switch info.kind {
        case .code: drawCodeBackground(at: point, lines: lines, edges: edges, in: context)
        case .quote: drawQuoteBar(at: point, lines: lines, in: context)
        case .rule: drawRule(at: point, lines: lines, in: context)
        case .image: drawImage(at: point, in: context)
        default: break
        }
        if info.kind != .code { drawInlineCode(at: point, lines: lines, checked: info.kind == .task && info.checked, in: context) }
        context.restoreGState()

        super.draw(at: point, in: context)

        if info.kind.isList, let first = lines.first {
            drawMarker(info, firstLine: first, at: point, in: context)
        }
    }

    // MARK: Blocks

    private func linesBounds(_ lines: [NSTextLineFragment]) -> CGRect {
        lines.reduce(CGRect.null) { $0.union($1.typographicBounds) }
    }

    private func drawCodeBackground(at point: CGPoint, lines: [NSTextLineFragment], edges: GroupEdges, in context: CGContext) {
        let text = linesBounds(lines)
        guard !text.isNull else { return }
        // Inner lines fill their whole fragment so the block reads as one surface: fragments
        // tile exactly, while an empty line's text bounds fall short of its line box and left
        // a seam. Only the block's first and last lines stop at the padded text edge.
        let shift = style.baselineCorrection(.code)
        let top = edges.contains(.first) ? text.minY + shift - style.px(8) : 0
        let bottom = edges.contains(.last) ? text.maxY + shift + style.px(12) : layoutFragmentFrame.height
        var rect = CGRect(x: point.x + containerMinX, y: point.y + top, width: containerWidth, height: bottom - top)
        // Snap the horizontal edges to device pixels so neighbouring lines meet without an
        // antialiased hairline.
        var device = context.convertToDeviceSpace(rect)
        let (minY, maxY) = (device.minY.rounded(), device.maxY.rounded())
        device.origin.y = minY
        device.size.height = maxY - minY
        rect = context.convertToUserSpace(device)
        let radius = style.px(12)
        let path = roundedPath(rect, radius: radius, roundTop: edges.contains(.first), roundBottom: edges.contains(.last))
        context.addPath(path)
        context.setFillColor(EditorStyle.codeBlockBackground.cgColor)
        context.fillPath()
    }

    /// The block's attachment, drawn where TextKit placed it.
    private func drawImage(at point: CGPoint, in context: CGContext) {
        guard let paragraph = textElement as? NSTextParagraph,
              paragraph.attributedString.length > 0,
              let attachment = paragraph.attributedString.attribute(.attachment, at: 0, effectiveRange: nil) as? ImageAttachment
        else { return }
        let frame = frameForTextAttachment(at: rangeInElement.location)
        guard !frame.isEmpty else { return }
        let url = attachments?.url(for: attachment.ref.attachmentId)
        ImageBlockRenderer.draw(attachment, in: frame.offsetBy(dx: point.x, dy: point.y), url: url, context: context)
    }

    private func drawQuoteBar(at point: CGPoint, lines: [NSTextLineFragment], in context: CGContext) {
        let text = linesBounds(lines)
        guard !text.isNull else { return }
        let rect = CGRect(x: point.x + containerMinX, y: point.y + text.minY + style.baselineCorrection(.quote), width: 2, height: text.height)
        context.addPath(CGPath(roundedRect: rect, cornerWidth: 1, cornerHeight: 1, transform: nil))
        context.setFillColor(Theme.accent.cgColor)
        context.fillPath()
    }

    private func drawRule(at point: CGPoint, lines: [NSTextLineFragment], in context: CGContext) {
        let text = linesBounds(lines)
        let y = text.isNull ? 0 : text.midY
        let rect = CGRect(x: point.x + containerMinX, y: point.y + y - 1, width: containerWidth, height: 2)
        context.addPath(CGPath(roundedRect: rect, cornerWidth: 1, cornerHeight: 1, transform: nil))
        context.setFillColor(Theme.borderSecondary.cgColor)
        context.fillPath()
    }

    // MARK: Inline code pills

    private func drawInlineCode(at point: CGPoint, lines: [NSTextLineFragment], checked: Bool, in context: CGContext) {
        let codeSize = style.fontSize(.paragraph) * 0.835
        let pad = (codeSize * 0.4).rounded()
        context.setFillColor((checked ? EditorStyle.inlineCodeBackgroundChecked : EditorStyle.inlineCodeBackground).cgColor)
        for line in lines {
            let string = line.attributedString
            let range = line.characterRange
            guard range.length > 0 else { continue }
            string.enumerateAttribute(.jotMarks, in: range) { value, runRange, _ in
                guard Marks(rawValue: value as? Int ?? 0).contains(.code) else { return }
                let font = string.attribute(.font, at: runRange.location, effectiveRange: nil) as? NSFont
                    ?? Fonts.mono(size: codeSize)
                let start = line.locationForCharacter(at: runRange.location)
                let end = line.locationForCharacter(at: NSMaxRange(runRange))
                let baseline = line.typographicBounds.minY + line.glyphOrigin.y
                // An inline element's background covers the code font's content area.
                let height = font.ascender - font.descender
                let rect = CGRect(
                    x: point.x + line.typographicBounds.minX + start.x - pad,
                    y: point.y + baseline - font.ascender,
                    // TextKit 2 reports the glyph edge without the trailing kern, so pad both sides.
                    width: end.x - start.x + pad * 2,
                    height: height
                )
                let radius = codeSize * 0.5
                context.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
                context.fillPath()
            }
        }
    }

    // MARK: List markers

    private func drawMarker(_ info: ParagraphInfo, firstLine line: NSTextLineFragment, at point: CGPoint, in context: CGContext) {
        let bounds = line.typographicBounds
        let textX = point.x + bounds.minX
        let baseline = point.y + bounds.minY + line.glyphOrigin.y
        let font = style.baseFont(info.kind)

        switch info.kind {
        case .bullet:
            let glyph = ["•", "◦", "▪"][min(info.indent, 2)]
            let attributed = NSAttributedString(string: glyph, attributes: [.font: font, .foregroundColor: Theme.accent])
            let width = attributed.size().width
            // `.bullet-list-marker { bottom: -1px }`
            drawText(attributed, x: textX - style.px(11) - width, baseline: baseline + 1, in: context)
        case .ordered:
            let number = paragraphAttributes[.jotOrdinal] as? Int ?? 1
            // `.prosemirror-flat-list[data-list-kind=ordered]:before { font-variant-numeric: tabular-nums }`
            let numberFont = Fonts.inter(size: font.pointSize, tabularNumbers: true)
            let attributed = NSAttributedString(string: "\(number).", attributes: [.font: numberFont, .foregroundColor: Theme.accent])
            let width = attributed.size().width
            // `::before { margin-top: 1px; transform: translate(-.3em) }`
            drawText(attributed, x: textX - font.pointSize * 0.3 - width, baseline: baseline + 1, in: context)
        case .task:
            let rect = checkboxRect(textX: textX, baseline: baseline)
            drawCheckbox(rect, checked: info.checked, in: context)
        default:
            break
        }
    }

    /// `input { display: grid; bottom: calc(-3 * var(--spx)) }` on the text baseline.
    func checkboxRect(textX: CGFloat, baseline: CGFloat) -> CGRect {
        let size = style.px(14)
        return CGRect(x: textX - style.px(22), y: baseline + 3 * style.zoom - size, width: size, height: size)
    }

    private func drawCheckbox(_ rect: CGRect, checked: Bool, in context: CGContext) {
        let border = 1.5 * style.zoom
        let alpha: CGFloat = checked ? 0.7 : 1
        let outline = rect.insetBy(dx: border / 2, dy: border / 2)
        let radius = style.px(5)
        context.addPath(CGPath(roundedRect: outline, cornerWidth: radius - border / 2, cornerHeight: radius - border / 2, transform: nil))
        context.setStrokeColor(Theme.accent(alpha).cgColor)
        context.setLineWidth(border)
        context.strokePath()
        if checked {
            let inner = style.px(8)
            let dot = CGRect(x: rect.midX - inner / 2, y: rect.midY - inner / 2, width: inner, height: inner)
            let r = 2.5 * style.zoom
            context.addPath(CGPath(roundedRect: dot, cornerWidth: r, cornerHeight: r, transform: nil))
            context.setFillColor(Theme.accent(alpha).cgColor)
            context.fillPath()
        }
    }

    /// Draws an attributed string with its baseline at `baseline` (flipped coordinates).
    private func drawText(_ string: NSAttributedString, x: CGFloat, baseline: CGFloat, in context: CGContext) {
        let line = CTLineCreateWithAttributedString(string)
        context.saveGState()
        context.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        context.textPosition = CGPoint(x: x, y: baseline)
        CTLineDraw(line, context)
        context.restoreGState()
    }

    private func roundedPath(_ rect: CGRect, radius: CGFloat, roundTop: Bool, roundBottom: Bool) -> CGPath {
        let path = CGMutablePath()
        let tr = roundTop ? radius : 0
        let br = roundBottom ? radius : 0
        // Flipped coordinates: minY is the visual top.
        path.move(to: CGPoint(x: rect.minX + tr, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - tr, y: rect.minY))
        path.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.minY), tangent2End: CGPoint(x: rect.maxX, y: rect.minY + tr), radius: tr)
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - br))
        path.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.maxY), tangent2End: CGPoint(x: rect.maxX - br, y: rect.maxY), radius: br)
        path.addLine(to: CGPoint(x: rect.minX + br, y: rect.maxY))
        path.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.maxY), tangent2End: CGPoint(x: rect.minX, y: rect.maxY - br), radius: br)
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + tr))
        path.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.minY), tangent2End: CGPoint(x: rect.minX + tr, y: rect.minY), radius: tr)
        path.closeSubpath()
        return path
    }
}
