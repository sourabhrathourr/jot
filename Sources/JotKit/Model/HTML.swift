import Foundation

/// HTML export ("Copy Note As… → HTML", "Export… → HTML"), shaped like Tiptap's `getHTML()`.
public nonisolated enum HTMLExporter {
    public static func html(_ blocks: [Block]) -> String {
        var out = ""
        var index = 0
        while index < blocks.count {
            let block = blocks[index]
            switch block.kind {
            case .paragraph: out += "<p>\(inline(block.runs))</p>"
            case .heading1, .heading2, .heading3:
                let level = block.kind.headingLevel ?? 1
                out += "<h\(level)>\(inline(block.runs))</h\(level)>"
            case .rule: out += "<hr>"
            case .image:
                // Tiptap's `renderHTML` for Raycast's image node.
                let id = escape(block.image?.attachmentId ?? "")
                out += "<div data-note-image data-attachment-id=\"\(id)\">[Image]</div>"
            case .quote:
                var lines: [String] = []
                while index < blocks.count, blocks[index].kind == .quote { lines.append("<p>\(inline(blocks[index].runs))</p>"); index += 1 }
                out += "<blockquote>\(lines.joined())</blockquote>"
                continue
            case .code:
                // Tiptap's `renderHTML`: `<pre><code class="language-…">`.
                let attributes = block.language.map { " class=\"language-\(escape($0))\"" } ?? ""
                var lines: [String] = []
                while index < blocks.count, blocks[index].kind == .code { lines.append(escape(blocks[index].text)); index += 1 }
                out += "<pre><code\(attributes)>\(lines.joined(separator: "\n"))</code></pre>"
                continue
            case .bullet, .ordered, .task:
                out += list(blocks, &index, indent: block.indent)
                continue
            }
            index += 1
        }
        return out
    }

    private static func list(_ blocks: [Block], _ index: inout Int, indent: Int) -> String {
        let kind = blocks[index].kind
        let tag = kind == .ordered ? "ol" : "ul"
        var out = kind == .task ? "<ul data-type=\"taskList\">" : "<\(tag)>"
        while index < blocks.count, blocks[index].kind.isList, blocks[index].indent >= indent {
            let block = blocks[index]
            if block.indent > indent {
                out += list(blocks, &index, indent: block.indent)
                continue
            }
            if block.kind == .task {
                out += "<li data-checked=\"\(block.checked)\"><p>\(inline(block.runs))</p></li>"
            } else {
                out += "<li><p>\(inline(block.runs))</p></li>"
            }
            index += 1
        }
        return out + (kind == .task ? "</ul>" : "</\(tag)>")
    }

    private static func inline(_ runs: [Run]) -> String {
        runs.map { run in
            var text = escape(run.text).replacingOccurrences(of: "\u{2028}", with: "<br>")
            if run.marks.contains(.code) { text = "<code>\(text)</code>" }
            if run.marks.contains(.bold) { text = "<strong>\(text)</strong>" }
            if run.marks.contains(.italic) { text = "<em>\(text)</em>" }
            if run.marks.contains(.strike) { text = "<s>\(text)</s>" }
            if run.marks.contains(.underline) { text = "<u>\(text)</u>" }
            if let link = run.link { text = "<a href=\"\(escape(link))\" target=\"_blank\">\(text)</a>" }
            return text
        }.joined()
    }

    private static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }
}
