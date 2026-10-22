import Foundation

/// Raycast's two plain-text serializers, ported over the document's Tiptap shape:
/// - `document` is the note's text (`serializers.toText`): what's stored, counted, used for the
///   title, and what "Copy Note As… Plain Text" and "Export… Plain Text" write.
/// - `clipboard` is what ⌘C puts on the pasteboard as `text/plain`: Markdown-flavoured across
///   blocks, the raw text when the selection stays inside one block.
public nonisolated enum PlainText {
    // MARK: Tiptap-shaped nodes

    /// A top-level node of the document, the way Tiptap would hold `[Block]`.
    enum Node {
        case paragraph([Run])
        case heading(Int, [Run])
        case quote([[Run]])
        case code(language: String?, text: String)
        case rule
        case image
        case list(ListItem)
    }

    /// A flat-list `list` node: its paragraph, then nested `list` nodes.
    struct ListItem {
        var kind: BlockKind
        var checked: Bool
        var runs: [Run]
        var children: [ListItem] = []
    }

    static func nodes(_ blocks: [Block]) -> [Node] {
        var nodes: [Node] = []
        var index = 0
        while index < blocks.count {
            let block = blocks[index]
            switch block.kind {
            case .paragraph:
                nodes.append(.paragraph(block.runs))
                index += 1
            case .heading1, .heading2, .heading3:
                nodes.append(.heading(block.kind.headingLevel ?? 1, block.runs))
                index += 1
            case .rule:
                nodes.append(.rule)
                index += 1
            case .image:
                nodes.append(.image)
                index += 1
            case .quote:
                var paragraphs: [[Run]] = []
                while index < blocks.count, blocks[index].kind == .quote {
                    paragraphs.append(blocks[index].runs)
                    index += 1
                }
                nodes.append(.quote(paragraphs))
            case .code:
                var lines: [String] = []
                while index < blocks.count, blocks[index].kind == .code {
                    lines.append(blocks[index].text)
                    index += 1
                }
                nodes.append(.code(language: block.language, text: lines.joined(separator: "\n")))
            case .bullet, .ordered, .task:
                // One top-level `list` node per item at the run's base depth; deeper items nest.
                let base = block.indent
                var items: [ListItem] = []
                while index < blocks.count, blocks[index].kind.isList {
                    let item = blocks[index]
                    let node = ListItem(kind: item.kind, checked: item.checked, runs: item.runs)
                    if item.indent <= base || items.isEmpty {
                        items.append(node)
                    } else {
                        insert(node, depth: item.indent - base, into: &items[items.count - 1])
                    }
                    index += 1
                }
                nodes.append(contentsOf: items.map(Node.list))
            }
        }
        return nodes
    }

    private static func insert(_ node: ListItem, depth: Int, into parent: inout ListItem) {
        if depth <= 1 || parent.children.isEmpty {
            parent.children.append(node)
        } else {
            insert(node, depth: depth - 1, into: &parent.children[parent.children.count - 1])
        }
    }

    /// Inline text: hard breaks become newlines.
    static func text(_ runs: [Run]) -> String {
        runs.map(\.text).joined().replacingOccurrences(of: "\u{2028}", with: "\n")
    }

    // MARK: Document text (`yn`)

    /// Blocks separated by a blank line; a run of list items is one chunk, one item per line
    /// without markers; empty blocks (and rules) are left out.
    public static func document(_ blocks: [Block]) -> String {
        var chunks: [String] = []
        var listRun: [String] = []
        func flushList() {
            if !listRun.isEmpty { chunks.append(listRun.joined(separator: "\n")) }
            listRun = []
        }
        for node in nodes(blocks) {
            if case .list(let item) = node {
                let text = listText(item)
                if !text.isEmpty { listRun.append(text) }
                continue
            }
            flushList()
            let text = nodeText(node)
            if !text.isEmpty { chunks.append(text) }
        }
        flushList()
        return chunks.joined(separator: "\n\n")
    }

    /// `vn`: the item's text and its nested items, one per line.
    private static func listText(_ item: ListItem) -> String {
        ([text(item.runs)] + item.children.map(listText)).filter { !$0.isEmpty }.joined(separator: "\n")
    }

    /// `_n`: the concatenated text of a node (a blockquote's paragraphs run together, as in Raycast).
    private static func nodeText(_ node: Node) -> String {
        switch node {
        case .paragraph(let runs), .heading(_, let runs): text(runs)
        case .quote(let paragraphs): paragraphs.map(text).joined()
        case .code(_, let code): code
        case .rule: ""
        case .image: "[Image]"
        case .list(let item): listText(item)
        }
    }

    // MARK: Clipboard text (`fh`)

    /// `partial` is true for an ordinary text selection (its slice is open); false when the
    /// whole document is selected.
    public static func clipboard(_ blocks: [Block], partial: Bool) -> String {
        let nodes = nodes(blocks)
        if partial, nodes.count == 1, let node = nodes.first {
            return within(node)
        }
        return markdown(nodes)
    }

    /// `lh`: a selection inside a single node copies that node's text; a list item with nested
    /// items or a multi-paragraph quote falls back to the Markdown form.
    private static func within(_ node: Node) -> String {
        switch node {
        case .code(_, let code): return code
        case .paragraph(let runs), .heading(_, let runs): return text(runs)
        case .quote(let paragraphs):
            return paragraphs.count == 1 ? text(paragraphs[0]) : markdown(paragraphs.map(Node.paragraph))
        case .list(let item):
            return item.children.isEmpty ? text(item.runs) : markdown([node])
        case .rule, .image: return markdown([node])
        }
    }

    /// `ch`: Markdown-flavoured blocks separated by a blank line; consecutive list items share
    /// one chunk; empty output is skipped.
    static func markdown(_ nodes: [Node]) -> String {
        var chunks: [String] = []
        var counter = 0
        var previousWasList = false
        for node in nodes {
            var isOrderedList = false
            if case .list(let item) = node, item.kind == .ordered { isOrderedList = true }
            if !isOrderedList { counter = 0 }
            let text = blockMarkdown(node, counter: &counter)
            if case .list = node, previousWasList, !chunks.isEmpty, !text.isEmpty {
                let last = chunks.removeLast()
                chunks.append(last.isEmpty ? text : last + "\n" + text)
            } else if !text.isEmpty {
                chunks.append(text)
            }
            if case .list = node { previousWasList = true } else { previousWasList = false }
        }
        return chunks.joined(separator: "\n\n")
    }

    /// `rh`.
    private static func blockMarkdown(_ node: Node, counter: inout Int) -> String {
        switch node {
        case .paragraph(let runs): return text(runs)
        case .heading(let level, let runs): return String(repeating: "#", count: level) + " " + text(runs)
        case .quote(let paragraphs):
            // `th`, including its trailing "> " line.
            let body = paragraphs.map(text).filter { !$0.isEmpty }.joined(separator: "\n\n")
            let quoted = body.components(separatedBy: "\n").map { "> " + $0 }.joined(separator: "\n")
            return quoted.isEmpty ? "> " : quoted + "\n> "
        case .code(let language, let code): return "```" + (language ?? "") + "\n" + code + "\n```"
        case .rule: return "---"
        case .image: return "[Image]"
        case .list(let item): return listMarkdown(item, depth: 0, counter: &counter)
        }
    }

    /// `nh`: two spaces per level, "- ", "N. ", or "- [ ]  " / "- [x]  " (two spaces, as Raycast).
    private static func listMarkdown(_ item: ListItem, depth: Int, counter: inout Int) -> String {
        let indent = String(repeating: "  ", count: depth)
        let marker: String
        switch item.kind {
        case .ordered:
            counter += 1
            marker = "\(counter). "
        case .task: marker = item.checked ? "- [x]  " : "- [ ]  "
        default: marker = "- "
        }
        var lines = [indent + marker + text(item.runs).trimmingTrailingWhitespace()]
        var childCounter = 0
        for child in item.children {
            if child.kind != .ordered { childCounter = 0 }
            lines.append(listMarkdown(child, depth: depth + 1, counter: &childCounter))
        }
        return lines.joined(separator: "\n")
    }
}

private nonisolated extension String {
    /// JavaScript's `trimEnd()`.
    func trimmingTrailingWhitespace() -> String {
        var end = endIndex
        while end > startIndex, self[index(before: end)].isWhitespace { end = index(before: end) }
        return String(self[..<end])
    }
}
