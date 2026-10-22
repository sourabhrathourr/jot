import Foundation
import ImageIO
import Testing
@testable import JotKit

struct TiptapCodecTests {
    let sample: [Block] = [
        Block(kind: .heading1, runs: [Run(text: "Title")]),
        Block(kind: .paragraph, runs: [Run(text: "Hi "), Run(text: "there", marks: [.bold, .italic]), Run(text: " link", link: "https://x.y")]),
        Block(kind: .bullet, runs: [Run(text: "a")]),
        Block(kind: .bullet, indent: 1, runs: [Run(text: "a.1")]),
        Block(kind: .task, checked: true, runs: [Run(text: "done")]),
        Block(kind: .ordered, runs: [Run(text: "one")]),
        Block(kind: .quote, runs: [Run(text: "q1")]),
        Block(kind: .quote, runs: [Run(text: "q2")]),
        Block(kind: .code, language: "swift", runs: [Run(text: "let x = 1")]),
        Block(kind: .code, language: "swift", runs: []),
        Block(kind: .code, language: "swift", runs: [Run(text: "print(x)")]),
        Block(kind: .rule),
        .image(ImageRef(attachmentId: "01ABC", width: 1200, height: 800)),
        Block(kind: .paragraph, runs: [Run(text: "line\u{2028}break")]),
    ]

    @Test func `round-trips every block type`() throws {
        let json = TiptapCodec.encodeString(sample)
        let decoded = try #require(TiptapCodec.decodeString(json))
        #expect(decoded == sample)
    }

    @Test func `nested list items live inside their parent list node`() {
        let doc = TiptapCodec.encode(sample)
        let list = doc.content?[2]
        #expect(list?.type == "list")
        #expect(list?.content?.count == 2)
        #expect(list?.content?[1].type == "list")
    }

    @Test func `decodes Raycast's own welcome-note shape`() throws {
        let json = #"{"type":"doc","content":[{"type":"heading","attrs":{"level":1},"content":[{"type":"text","text":"Welcome"}]},{"type":"paragraph","content":[{"type":"text","marks":[{"type":"link","attrs":{"href":"https://www.raycast.com/pro","target":"_blank"}}],"text":"Raycast Pro"}]},{"type":"horizontalRule"}]}"#
        let blocks = try #require(TiptapCodec.decodeString(json))
        #expect(blocks.map(\.kind) == [.heading1, .paragraph, .rule])
        #expect(blocks[1].runs.first?.link == "https://www.raycast.com/pro")
    }

    @Test func `title is the first non-empty line, else Untitled`() {
        #expect([Block.paragraph(""), Block.paragraph("  Hello ")].title == "Hello")
        #expect([Block.paragraph("")].title == "Untitled")
    }
}

struct ImageTests {
    /// A solid PNG (or TIFF) of the given size, made in memory.
    static func image(width: Int, height: Int, type: CFString = "public.png" as CFString) -> Data {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 1, green: 0.39, blue: 0.39, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(data, type, 1, nil)!
        CGImageDestinationAddImage(destination, context.makeImage()!, nil)
        CGImageDestinationFinalize(destination)
        return data as Data
    }

    @Test func `the store keeps the pixel size and turns TIFF into PNG`() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = AttachmentStore(directory: directory)

        let png = try store.add(Self.image(width: 300, height: 200))
        #expect(png.width == 300 && png.height == 200)
        #expect(store.url(for: png.attachmentId)?.pathExtension == "png")

        let tiff = try store.add(Self.image(width: 40, height: 50, type: "public.tiff" as CFString))
        #expect(store.url(for: tiff.attachmentId)?.pathExtension == "png")
        #expect(throws: AttachmentStore.Failure.self) { try store.add(Data("not an image".utf8)) }
    }

    @Test func `images show at Raycast's size`() {
        let wide = ImageAttachment.displaySize(ImageRef(attachmentId: "a", width: 2000, height: 1000), available: 480)
        #expect(wide == CGSize(width: 480, height: 240))
        let tall = ImageAttachment.displaySize(ImageRef(attachmentId: "a", width: 600, height: 1200), available: 480)
        #expect(tall == CGSize(width: 240, height: 480))
        let small = ImageAttachment.displaySize(ImageRef(attachmentId: "a", width: 100, height: 50), available: 480)
        #expect(small == CGSize(width: 100, height: 50))
    }

    @Test func `an image is [Image] in text and Markdown`() {
        let blocks: [Block] = [.paragraph("a"), .image(ImageRef(attachmentId: "x")), .paragraph("b")]
        #expect(blocks.plainText == "a\n\n[Image]\n\nb")
        #expect(MarkdownExporter.markdown(blocks) == "a\n\n[Image]\n\nb")
    }
}

struct PlainTextTests {
    @Test func `note text is Raycast's toText: lists one per line, code keeps its newlines`() {
        let blocks: [Block] = [
            Block(kind: .heading1, runs: [Run(text: "Title")]),
            Block.paragraph(""),
            Block(kind: .bullet, runs: [Run(text: "a")]),
            Block(kind: .task, indent: 1, runs: [Run(text: "b")]),
            Block(kind: .code, runs: [Run(text: "x")]),
            Block(kind: .code, runs: []),
            Block(kind: .code, runs: [Run(text: "y")]),
            Block(kind: .rule),
            Block(kind: .quote, runs: [Run(text: "q1")]),
            Block(kind: .quote, runs: [Run(text: "q2")]),
            Block(kind: .paragraph, runs: [Run(text: "line\u{2028}break")]),
        ]
        #expect(blocks.plainText == "Title\n\na\nb\n\nx\n\ny\n\nq1q2\n\nline\nbreak")
    }

    @Test func `clipboard text is Raycast's markdown flavour across blocks`() {
        let blocks: [Block] = [
            Block(kind: .heading2, runs: [Run(text: "H")]),
            Block(kind: .ordered, runs: [Run(text: "one")]),
            Block(kind: .ordered, runs: [Run(text: "two")]),
            Block(kind: .task, indent: 1, checked: true, runs: [Run(text: "done")]),
            Block(kind: .quote, runs: [Run(text: "q")]),
            Block(kind: .rule),
        ]
        #expect(PlainText.clipboard(blocks, partial: true) == "## H\n\n1. one\n2. two\n  - [x]  done\n\n> q\n> \n\n---")
        #expect(PlainText.clipboard([Block(kind: .heading1, runs: [Run(text: "H")])], partial: true) == "H")
    }

    @Test func `markdown import keeps lists, tasks and code languages`() {
        let blocks = MarkdownImporter.blocks("# A\n- [ ] t\n  - n\n1. o\n\n> q\n\n```rb\nx\n```\n***")
        #expect(blocks.map(\.kind) == [.heading1, .task, .bullet, .ordered, .quote, .code, .rule])
        #expect(blocks.map(\.indent) == [0, 0, 1, 0, 0, 0, 0])
        #expect(blocks[5].language == "rb")
    }
}

struct MarkdownTests {
    @Test func `exports blocks as markdown`() {
        let blocks: [Block] = [
            Block(kind: .heading2, runs: [Run(text: "Plan")]),
            Block(kind: .ordered, runs: [Run(text: "a")]),
            Block(kind: .ordered, runs: [Run(text: "b", marks: .bold)]),
            Block(kind: .task, indent: 1, checked: true, runs: [Run(text: "c")]),
            Block(kind: .code, language: "go", runs: [Run(text: "x")]),
            Block(kind: .paragraph, runs: [Run(text: "see", link: "https://a.b"), Run(text: " "), Run(text: "it", marks: .code)]),
        ]
        #expect(MarkdownExporter.markdown(blocks) == """
            ## Plan

            1. a
            2. **b**
              - [x] c

            ```go
            x
            ```

            [see](https://a.b) `it`
            """)
    }
}

struct RepositoryTests {
    let repository: NotesRepository

    init() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("jot-\(UUID()).db").path
        repository = try NotesRepository(path: path)
    }

    @Test func `creates, saves, pins and soft-deletes notes`() throws {
        let note = repository.create(blocks: [.paragraph("First")])
        repository.save(id: note.id, blocks: [.paragraph("Renamed"), .paragraph("body")], caret: 3)
        let saved = try #require(repository.note(id: note.id))
        #expect(saved.title == "Renamed")
        #expect(saved.text == "Renamed\n\nbody")
        #expect(saved.caretPosition == 3)

        let other = repository.create(blocks: [.paragraph("Second")])
        repository.setPinned(id: note.id, true)
        #expect(repository.list().map(\.id) == [note.id, other.id])
        #expect(repository.list(search: "secon").map(\.id) == [other.id])

        repository.delete(id: note.id)
        #expect(repository.list().map(\.id) == [other.id])
    }

    @Test func `ids are sortable ULIDs`() {
        let a = ULID.make(date: Date(timeIntervalSince1970: 1))
        let b = ULID.make(date: Date(timeIntervalSince1970: 2))
        #expect(a.count == 26)
        #expect(a < b)
    }
}
