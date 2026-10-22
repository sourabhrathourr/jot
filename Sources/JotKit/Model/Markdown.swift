import Foundation

/// Markdown export, matching what "Copy Note As… Markdown" produces in Raycast.
public nonisolated enum MarkdownExporter {
    public static func markdown(_ blocks: [Block]) -> String {
        var lines: [String] = []
        var orderedCounters: [Int: Int] = [:]
        var previous: BlockKind?

        for (i, block) in blocks.enumerated() {
            if block.kind != .ordered { orderedCounters.removeAll() }
            let indent = String(repeating: "  ", count: block.indent)
            let body = inline(block.runs)
            let needsGap = previous.map { separated($0, block.kind) } ?? false
            if needsGap { lines.append("") }

            switch block.kind {
            case .paragraph: lines.append(body)
            case .image: lines.append("[Image]")
            case .heading1: lines.append("# " + body)
            case .heading2: lines.append("## " + body)
            case .heading3: lines.append("### " + body)
            case .bullet: lines.append(indent + "- " + body)
            case .task: lines.append(indent + (block.checked ? "- [x] " : "- [ ] ") + body)
            case .ordered:
                orderedCounters = orderedCounters.filter { $0.key <= block.indent }
                let n = (orderedCounters[block.indent] ?? 0) + 1
                orderedCounters[block.indent] = n
                lines.append(indent + "\(n). " + body)
            case .quote: lines.append("> " + body)
            case .rule: lines.append("---")
            case .code:
                let isFirst = i == 0 || blocks[i - 1].kind != .code
                let isLast = i == blocks.count - 1 || blocks[i + 1].kind != .code
                if isFirst { lines.append("```" + (block.language ?? "")) }
                lines.append(block.text)
                if isLast { lines.append("```") }
            }
            previous = block.kind
        }
        return lines.joined(separator: "\n")
    }

    /// Blank lines between different block groups; list items and quote lines stay tight.
    private static func separated(_ a: BlockKind, _ b: BlockKind) -> Bool {
        if a.isList && b.isList { return false }
        if a == b && (a == .quote || a == .code) { return false }
        return true
    }

    private static func inline(_ runs: [Run]) -> String {
        runs.map { run in
            var text = run.text.replacingOccurrences(of: "\u{2028}", with: "  \n")
            if run.marks.contains(.code) {
                text = "`" + text + "`"
            } else {
                if run.marks.contains(.bold) { text = "**" + text + "**" }
                if run.marks.contains(.italic) { text = "*" + text + "*" }
                if run.marks.contains(.strike) { text = "~~" + text + "~~" }
                if run.marks.contains(.underline) { text = "<u>" + text + "</u>" }
            }
            if let link = run.link { text = "[" + text + "](" + link + ")" }
            return text
        }.joined()
    }
}
