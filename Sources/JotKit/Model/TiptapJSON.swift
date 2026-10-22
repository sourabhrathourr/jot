import Foundation

/// A ProseMirror/Tiptap JSON node, the format Raycast stores in `notes.raw_content`.
/// Lists use prosemirror-flat-list (`{type: "list", attrs: {kind, checked}}`).
public nonisolated struct PMNode: Codable, Equatable, Sendable {
    public var type: String
    public var attrs: [String: JSONValue]?
    public var content: [PMNode]?
    public var text: String?
    public var marks: [PMMark]?

    public init(type: String, attrs: [String: JSONValue]? = nil, content: [PMNode]? = nil, text: String? = nil, marks: [PMMark]? = nil) {
        self.type = type
        self.attrs = attrs
        self.content = content
        self.text = text
        self.marks = marks
    }
}

public nonisolated struct PMMark: Codable, Equatable, Sendable {
    public var type: String
    public var attrs: [String: JSONValue]?
}

public nonisolated enum JSONValue: Codable, Equatable, Sendable {
    case string(String), number(Double), bool(Bool), null

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let n = try? c.decode(Double.self) { self = .number(n) }
        else { self = .string(try c.decode(String.self)) }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let s): try c.encode(s)
        case .number(let n): try c.encode(n)
        case .bool(let b): try c.encode(b)
        case .null: try c.encodeNil()
        }
    }

    var stringValue: String? { if case .string(let s) = self { s } else { nil } }
    var boolValue: Bool? { if case .bool(let b) = self { b } else { nil } }
    var intValue: Int? { if case .number(let n) = self { Int(n) } else { nil } }
}

/// Converts between flat `[Block]` and nested Tiptap JSON.
public nonisolated enum TiptapCodec {
    public static func encode(_ blocks: [Block]) -> PMNode {
        var output: [PMNode] = []
        var index = 0
        while index < blocks.count {
            let block = blocks[index]
            switch block.kind {
            case .bullet, .ordered, .task:
                output.append(contentsOf: encodeLists(blocks, &index, indent: block.indent))
                continue
            case .quote:
                var paragraphs: [PMNode] = []
                while index < blocks.count, blocks[index].kind == .quote {
                    paragraphs.append(paragraph(blocks[index].runs))
                    index += 1
                }
                output.append(PMNode(type: "blockquote", content: paragraphs))
                continue
            case .code:
                let language = block.language
                var lines: [String] = []
                while index < blocks.count, blocks[index].kind == .code {
                    lines.append(blocks[index].text)
                    index += 1
                }
                let text = lines.joined(separator: "\n")
                output.append(PMNode(
                    type: "codeBlock",
                    attrs: ["language": language.map(JSONValue.string) ?? .null],
                    content: text.isEmpty ? nil : [PMNode(type: "text", text: text)]
                ))
                continue
            case .rule:
                output.append(PMNode(type: "horizontalRule"))
            case .image:
                // Raycast's image node: `attachmentId`, `uploadId`, `status`, `width`, `height`.
                let image = block.image
                output.append(PMNode(type: "image", attrs: [
                    "attachmentId": image.map { .string($0.attachmentId) } ?? .null,
                    "uploadId": .null,
                    "status": .string("ready"),
                    "width": image?.width.map { .number(Double($0)) } ?? .null,
                    "height": image?.height.map { .number(Double($0)) } ?? .null,
                ]))
            case .heading1, .heading2, .heading3:
                output.append(PMNode(
                    type: "heading",
                    attrs: ["level": .number(Double(block.kind.headingLevel ?? 1))],
                    content: inline(block.runs)
                ))
            case .paragraph:
                output.append(paragraph(block.runs))
            }
            index += 1
        }
        return PMNode(type: "doc", content: output.isEmpty ? [PMNode(type: "paragraph")] : output)
    }

    /// Consecutive list blocks at `indent` or deeper become `list` nodes; deeper
    /// items nest inside the preceding item, as prosemirror-flat-list does.
    private static func encodeLists(_ blocks: [Block], _ index: inout Int, indent: Int) -> [PMNode] {
        var nodes: [PMNode] = []
        while index < blocks.count, blocks[index].kind.isList, blocks[index].indent >= indent {
            let block = blocks[index]
            if block.indent > indent, !nodes.isEmpty {
                let children = encodeLists(blocks, &index, indent: block.indent)
                nodes[nodes.count - 1].content = (nodes[nodes.count - 1].content ?? []) + children
                continue
            }
            let kind = switch block.kind {
            case .ordered: "ordered"
            case .task: "task"
            default: "bullet"
            }
            nodes.append(PMNode(
                type: "list",
                attrs: ["kind": .string(kind), "checked": .bool(block.checked), "collapsed": .bool(false), "order": .null],
                content: [paragraph(block.runs)]
            ))
            index += 1
        }
        return nodes
    }

    private static func paragraph(_ runs: [Run]) -> PMNode {
        PMNode(type: "paragraph", content: inline(runs))
    }

    private static func inline(_ runs: [Run]) -> [PMNode]? {
        var nodes: [PMNode] = []
        for run in runs where !run.text.isEmpty {
            let marks = pmMarks(run)
            let pieces = run.text.components(separatedBy: "\u{2028}")
            for (i, piece) in pieces.enumerated() {
                if i > 0 { nodes.append(PMNode(type: "hardBreak")) }
                if !piece.isEmpty { nodes.append(PMNode(type: "text", text: piece, marks: marks)) }
            }
        }
        return nodes.isEmpty ? nil : nodes
    }

    private static func pmMarks(_ run: Run) -> [PMMark]? {
        var marks: [PMMark] = []
        if run.marks.contains(.bold) { marks.append(PMMark(type: "bold")) }
        if run.marks.contains(.italic) { marks.append(PMMark(type: "italic")) }
        if run.marks.contains(.underline) { marks.append(PMMark(type: "underline")) }
        if run.marks.contains(.strike) { marks.append(PMMark(type: "strike")) }
        if run.marks.contains(.code) { marks.append(PMMark(type: "code")) }
        if let link = run.link {
            marks.append(PMMark(type: "link", attrs: ["href": .string(link), "target": .string("_blank")]))
        }
        return marks.isEmpty ? nil : marks
    }

    // MARK: Decoding

    public static func decode(_ doc: PMNode) -> [Block] {
        var blocks: [Block] = []
        for node in doc.content ?? [] {
            decodeBlock(node, indent: 0, into: &blocks)
        }
        return blocks.isEmpty ? [Block(kind: .paragraph)] : blocks
    }

    private static func decodeBlock(_ node: PMNode, indent: Int, into blocks: inout [Block]) {
        switch node.type {
        case "paragraph":
            blocks.append(Block(kind: .paragraph, runs: runs(node.content)))
        case "heading":
            let level = node.attrs?["level"]?.intValue ?? 1
            blocks.append(Block(kind: .heading(level), runs: runs(node.content)))
        case "horizontalRule":
            blocks.append(Block(kind: .rule))
        case "image":
            guard let id = node.attrs?["attachmentId"]?.stringValue, !id.isEmpty else { return }
            blocks.append(.image(ImageRef(
                attachmentId: id,
                width: node.attrs?["width"]?.intValue,
                height: node.attrs?["height"]?.intValue
            )))
        case "codeBlock":
            let text = (node.content ?? []).compactMap(\.text).joined()
            let language = node.attrs?["language"]?.stringValue.flatMap { $0.isEmpty ? nil : $0 }
            for line in text.components(separatedBy: "\n") {
                blocks.append(Block(kind: .code, language: language, runs: line.isEmpty ? [] : [Run(text: line)]))
            }
        case "blockquote":
            for child in node.content ?? [] {
                var nested: [Block] = []
                decodeBlock(child, indent: indent, into: &nested)
                blocks.append(contentsOf: nested.map { Block(kind: .quote, runs: $0.runs) })
            }
        case "list":
            let kind: BlockKind = switch node.attrs?["kind"]?.stringValue {
            case "ordered": .ordered
            case "task": .task
            default: .bullet
            }
            let checked = node.attrs?["checked"]?.boolValue ?? false
            var first = true
            for child in node.content ?? [] {
                if child.type == "paragraph" && first {
                    blocks.append(Block(kind: kind, indent: indent, checked: checked, runs: runs(child.content)))
                    first = false
                } else {
                    decodeBlock(child, indent: indent + 1, into: &blocks)
                }
            }
            if first { blocks.append(Block(kind: kind, indent: indent, checked: checked)) }
        // Tiptap's classic list nodes, in case a note came from a stock Tiptap editor.
        case "bulletList", "orderedList", "taskList":
            for item in node.content ?? [] {
                let kind: BlockKind = node.type == "orderedList" ? .ordered : node.type == "taskList" ? .task : .bullet
                let checked = item.attrs?["checked"]?.boolValue ?? false
                var first = true
                for child in item.content ?? [] {
                    if child.type == "paragraph" && first {
                        blocks.append(Block(kind: kind, indent: indent, checked: checked, runs: runs(child.content)))
                        first = false
                    } else {
                        decodeBlock(child, indent: indent + 1, into: &blocks)
                    }
                }
            }
        default:
            let text = runs(node.content)
            if !text.isEmpty { blocks.append(Block(kind: .paragraph, runs: text)) }
        }
    }

    private static func runs(_ nodes: [PMNode]?) -> [Run] {
        var result: [Run] = []
        for node in nodes ?? [] {
            switch node.type {
            case "text":
                var marks: Marks = []
                var link: String?
                for mark in node.marks ?? [] {
                    switch mark.type {
                    case "bold": marks.insert(.bold)
                    case "italic": marks.insert(.italic)
                    case "underline": marks.insert(.underline)
                    case "strike": marks.insert(.strike)
                    case "code": marks.insert(.code)
                    case "link": link = mark.attrs?["href"]?.stringValue
                    default: break
                    }
                }
                append(Run(text: node.text ?? "", marks: marks, link: link), to: &result)
            case "hardBreak":
                append(Run(text: "\u{2028}"), to: &result)
            default:
                break
            }
        }
        return result
    }

    private static func append(_ run: Run, to runs: inout [Run]) {
        if let last = runs.last, last.marks == run.marks, last.link == run.link {
            runs[runs.count - 1].text += run.text
        } else {
            runs.append(run)
        }
    }

    public static func encodeString(_ blocks: [Block]) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(encode(blocks)) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }

    public static func decodeString(_ json: String) -> [Block]? {
        guard let doc = try? JSONDecoder().decode(PMNode.self, from: Data(json.utf8)) else { return nil }
        return decode(doc)
    }
}
