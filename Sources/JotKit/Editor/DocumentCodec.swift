import AppKit

/// Text storage ⇄ `[Block]`. Each block is one paragraph terminated by "\n";
/// the storage always ends with a newline (Tiptap's trailing node, natively).
enum DocumentCodec {
    static func attributedString(_ blocks: [Block]) -> NSAttributedString {
        let result = NSMutableAttributedString()
        for block in blocks.isEmpty ? [Block(kind: .paragraph)] : blocks {
            let info = ParagraphInfo(kind: block.kind, indent: block.indent, checked: block.checked, language: block.language).attributes
            if block.kind == .image, let image = block.image {
                let character = NSMutableAttributedString(attachment: ImageAttachment(image))
                character.addAttributes(info, range: NSRange(location: 0, length: character.length))
                result.append(character)
                result.append(NSAttributedString(string: "\n", attributes: info))
                continue
            }
            for run in block.runs where !run.text.isEmpty {
                var attributes = info
                attributes[.jotMarks] = run.marks.rawValue
                if let link = run.link { attributes[.jotHref] = link }
                result.append(NSAttributedString(string: run.text, attributes: attributes))
            }
            result.append(NSAttributedString(string: "\n", attributes: info))
        }
        return result
    }

    static func blocks(_ text: NSAttributedString, in range: NSRange? = nil) -> [Block] {
        let source = range.map { text.attributedSubstring(from: $0) } ?? text
        let string = source.string as NSString
        var blocks: [Block] = []
        for paragraph in source.paragraphRanges {
            let info = source.paragraphInfo(at: paragraph)
            var contentRange = paragraph
            if contentRange.length > 0, string.character(at: NSMaxRange(contentRange) - 1) == 0x0A {
                contentRange.length -= 1
            }
            var runs: [Run] = []
            source.enumerateAttributes(in: contentRange) { attributes, runRange, _ in
                let marks = Marks(rawValue: attributes[.jotMarks] as? Int ?? 0)
                let href = attributes[.jotHref] as? String
                let text = string.substring(with: runRange)
                if let last = runs.last, last.marks == marks, last.link == href {
                    runs[runs.count - 1].text += text
                } else {
                    runs.append(Run(text: text, marks: marks, link: href))
                }
            }
            if info.kind == .image {
                // The block is its attachment; an image paragraph that lost it is dropped.
                if contentRange.length > 0, let attachment = source.attribute(.attachment, at: contentRange.location, effectiveRange: nil) as? ImageAttachment {
                    blocks.append(.image(attachment.ref))
                }
                continue
            }
            blocks.append(Block(kind: info.kind, indent: info.indent, checked: info.checked, language: info.language, runs: runs))
        }
        return blocks
    }
}
