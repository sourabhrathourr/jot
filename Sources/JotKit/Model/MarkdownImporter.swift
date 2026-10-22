import Foundation

/// Plain text pasted into a note, parsed the way Raycast's `clipboardTextParser` does: as
/// Markdown (`marked` with `breaks: true`, so a single newline is a hard break and only a blank
/// line starts a new paragraph). Very long text skips Markdown and becomes one paragraph per line.
public nonisolated enum MarkdownImporter {
    public static func blocks(_ markdown: String) -> [Block] {
        let text = markdown.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        guard text.count <= 100_000,
              let parsed = try? AttributedString(markdown: text, options: .init(interpretedSyntax: .full))
        else { return lines(text) }

        var blocks: [Block] = []
        var currentIdentity: Int?
        for run in parsed.runs {
            guard let intent = run.presentationIntent, let leaf = intent.components.first else { continue }
            let piece = String(parsed[run.range].characters)

            if leaf.identity != currentIdentity {
                currentIdentity = leaf.identity
                blocks.append(contentsOf: start(intent, text: piece))
                if case .codeBlock = leaf.kind { continue }
                if case .thematicBreak = leaf.kind { continue }
            } else if case .codeBlock = leaf.kind {
                continue
            }
            guard var last = blocks.popLast() else { continue }
            last.runs.append(contentsOf: inline(piece, run: run))
            blocks.append(last)
        }
        return blocks.map(taskItem)
    }

    /// The block(s) a new leaf intent opens. Code blocks and rules are complete on their own.
    private static func start(_ intent: PresentationIntent, text: String) -> [Block] {
        let components = intent.components
        switch components[0].kind {
        case .codeBlock(let language):
            var code = text
            if code.hasSuffix("\n") { code.removeLast() }
            let hint = language.flatMap { $0.isEmpty ? nil : $0 }
            return code.components(separatedBy: "\n").map {
                Block(kind: .code, language: hint, runs: $0.isEmpty ? [] : [Run(text: $0)])
            }
        case .thematicBreak:
            return [Block(kind: .rule)]
        case .header(let level) where level <= 3:
            return [Block(kind: .heading(level))]
        default:
            break
        }
        let lists = components.filter {
            if case .orderedList = $0.kind { return true }
            if case .unorderedList = $0.kind { return true }
            return false
        }
        if let innermost = lists.first {
            var ordered = false
            if case .orderedList = innermost.kind { ordered = true }
            return [Block(kind: ordered ? .ordered : .bullet, indent: lists.count - 1)]
        }
        if components.contains(where: { if case .blockQuote = $0.kind { return true }; return false }) {
            return [Block(kind: .quote)]
        }
        return [Block(kind: .paragraph)]
    }

    private static func inline(_ text: String, run: AttributedString.Runs.Run) -> [Run] {
        let intent = run.inlinePresentationIntent ?? []
        // `breaks: true`: soft line breaks are hard breaks.
        if intent.contains(.softBreak) || intent.contains(.lineBreak) { return [Run(text: "\u{2028}")] }
        var marks: Marks = []
        if intent.contains(.stronglyEmphasized) { marks.insert(.bold) }
        if intent.contains(.emphasized) { marks.insert(.italic) }
        if intent.contains(.code) { marks.insert(.code) }
        if intent.contains(.strikethrough) { marks.insert(.strike) }
        return [Run(text: text, marks: marks, link: run.link?.absoluteString)]
    }

    /// GFM task items (`- [ ] …`, `- [x] …`) arrive as list items starting with the box.
    private static func taskItem(_ block: Block) -> Block {
        guard block.kind == .bullet || block.kind == .ordered, let first = block.runs.first else { return block }
        for (prefix, checked) in [("[ ] ", false), ("[x] ", true), ("[X] ", true)] where first.text.hasPrefix(prefix) {
            var task = block
            task.kind = .task
            task.checked = checked
            task.runs[0].text.removeFirst(prefix.count)
            if task.runs[0].text.isEmpty { task.runs.removeFirst() }
            return task
        }
        return block
    }

    /// `mm`: one paragraph per line.
    static func lines(_ text: String) -> [Block] {
        text.components(separatedBy: "\n").map { Block.paragraph($0) }
    }
}
