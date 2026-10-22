import Foundation

/// The block types a note paragraph can be. One text paragraph = one block.
public nonisolated enum BlockKind: String, Sendable, CaseIterable {
    case paragraph
    case heading1, heading2, heading3
    case bullet, ordered, task
    case quote
    case code
    case rule
    /// An image, one per block (Raycast's `image` node: block, atom, draggable).
    case image

    var isList: Bool { self == .bullet || self == .ordered || self == .task }
    var isHeading: Bool { headingLevel != nil }

    var headingLevel: Int? {
        switch self {
        case .heading1: 1
        case .heading2: 2
        case .heading3: 3
        default: nil
        }
    }

    static func heading(_ level: Int) -> BlockKind {
        switch level {
        case 1: .heading1
        case 2: .heading2
        default: .heading3
        }
    }
}

/// Inline formatting carried by a run of text.
public nonisolated struct Marks: OptionSet, Hashable, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let bold = Marks(rawValue: 1 << 0)
    public static let italic = Marks(rawValue: 1 << 1)
    public static let underline = Marks(rawValue: 1 << 2)
    public static let strike = Marks(rawValue: 1 << 3)
    public static let code = Marks(rawValue: 1 << 4)
}

/// An image stored beside the database, referenced by id (Raycast's `attachmentId`).
public nonisolated struct ImageRef: Equatable, Hashable, Sendable {
    public var attachmentId: String
    /// Pixel size, known up front so the note lays out before the image is decoded.
    public var width: Int?
    public var height: Int?

    public init(attachmentId: String, width: Int? = nil, height: Int? = nil) {
        self.attachmentId = attachmentId
        self.width = width
        self.height = height
    }
}

public nonisolated struct Run: Equatable, Sendable {
    public var text: String
    public var marks: Marks = []
    public var link: String?

    public init(text: String, marks: Marks = [], link: String? = nil) {
        self.text = text
        self.marks = marks
        self.link = link
    }
}

/// A flat, editor-shaped view of a note: the common currency between the text
/// storage, the Tiptap JSON we persist, Markdown export and plain text.
public nonisolated struct Block: Equatable, Sendable {
    public var kind: BlockKind
    public var indent: Int = 0
    public var checked: Bool = false
    /// Code block language (Tiptap's `codeBlock.attrs.language`), repeated on each of its lines.
    public var language: String?
    /// The image of an `.image` block.
    public var image: ImageRef?
    public var runs: [Run] = []

    public init(kind: BlockKind, indent: Int = 0, checked: Bool = false, language: String? = nil, image: ImageRef? = nil, runs: [Run] = []) {
        self.kind = kind
        self.indent = indent
        self.checked = checked
        self.language = kind == .code ? language : nil
        self.image = kind == .image ? image : nil
        self.runs = kind == .image ? [] : runs
    }

    public static func image(_ image: ImageRef) -> Block {
        Block(kind: .image, image: image)
    }

    public var text: String { runs.map(\.text).joined() }

    public static func paragraph(_ text: String) -> Block {
        Block(kind: .paragraph, runs: text.isEmpty ? [] : [Run(text: text)])
    }
}

nonisolated extension [Block] {
    /// The note's text, as Raycast stores it and counts it (`serializers.toText`).
    public var plainText: String { PlainText.document(self) }

    /// Raycast's rule: the first non-empty line, else "Untitled".
    public var title: String {
        let line = plainText.split(separator: "\n", omittingEmptySubsequences: true).first
        let trimmed = line?.trimmingCharacters(in: .whitespaces) ?? ""
        return trimmed.isEmpty ? "Untitled" : trimmed
    }
}
