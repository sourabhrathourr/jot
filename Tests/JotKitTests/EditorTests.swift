import AppKit
import Testing
@testable import JotKit

/// Drives the real NSTextView the way typing does, then checks the resulting blocks.
@MainActor
struct EditorTests {
    let editor = NoteEditor()

    private func type(_ text: String) {
        for character in text {
            if character == "\n" {
                editor.textView.doCommand(by: #selector(NSResponder.insertNewline(_:)))
            } else {
                editor.textView.insertText(String(character), replacementRange: editor.textView.selectedRange())
            }
        }
    }

    private func backspace() {
        editor.textView.doCommand(by: #selector(NSResponder.deleteBackward(_:)))
    }

    private var kinds: [BlockKind] { editor.blocks.map(\.kind) }
    private var texts: [String] { editor.blocks.map(\.text) }

    private func command(_ selector: Selector) {
        editor.textView.doCommand(by: selector)
    }

    private func pasteboard() -> NSPasteboard {
        let board = NSPasteboard(name: NSPasteboard.Name("jot.tests.\(UUID().uuidString)"))
        board.clearContents()
        return board
    }

    private func paste(_ string: String) {
        let board = pasteboard()
        board.setString(string, forType: .string)
        _ = editor.textView.readSelection(from: board, type: .string)
    }

    @Test func `markdown prefixes turn into blocks`() {
        type("# Title\n## Sub\n- item\n1. first\n[] todo\n\n> quote")
        #expect(kinds == [.heading1, .heading2, .bullet, .ordered, .task, .quote, .paragraph])
        #expect(texts == ["Title", "Sub", "item", "first", "todo", "quote", ""])
    }

    @Test func `enter continues a list and an empty item exits it`() {
        type("- a\nb\n\nafter")
        // The empty paragraph is Tiptap's trailing node, added when "- " made the list the last block.
        #expect(kinds == [.bullet, .bullet, .paragraph, .paragraph])
        #expect(texts == ["a", "b", "after", ""])
    }

    @Test func `new task items start unchecked`() {
        type("[x] done\nnext")
        #expect(editor.blocks.map(\.checked) == [true, false, false])
    }

    @Test func `tab nests list items under the previous one`() {
        type("- a\nb")
        editor.textView.doCommand(by: #selector(NSResponder.insertTab(_:)))
        #expect(editor.blocks.map(\.indent) == [0, 1, 0])
        editor.textView.doCommand(by: #selector(NSResponder.insertBacktab(_:)))
        #expect(editor.blocks.map(\.indent) == [0, 0, 0])
    }

    @Test func `backspace at the start of a block turns it back into text`() {
        type("# Title")
        editor.textView.setSelectedRange(NSRange(location: 0, length: 0))
        backspace()
        #expect(kinds == [.paragraph, .paragraph])
        #expect(texts == ["Title", ""])
    }

    @Test func `backspace joins into the previous block, keeping its type`() {
        type("- a\n\nb")
        // "b" is a paragraph after the list; join it back into the item.
        editor.textView.setSelectedRange(NSRange(location: 2, length: 0))
        backspace()
        #expect(kinds == [.bullet, .paragraph])
        #expect(texts == ["ab", ""])
    }

    @Test func `inline markdown applies marks and drops the delimiters`() {
        type("a **b** *c* `d` ~~e~~")
        let runs = editor.blocks[0].runs
        #expect(editor.blocks[0].text == "a b c d e")
        #expect(runs.first { $0.text == "b" }?.marks == .bold)
        #expect(runs.first { $0.text == "c" }?.marks == .italic)
        #expect(runs.first { $0.text == "d" }?.marks == .code)
        #expect(runs.first { $0.text == "e" }?.marks == .strike)
    }

    @Test func `typing after an inline rule is unformatted`() {
        type("**b** c")
        #expect(editor.blocks[0].runs.last == Run(text: " c"))
    }

    @Test func `three dashes make a horizontal rule`() {
        type("---after")
        #expect(kinds == [.rule, .paragraph])
        #expect(texts == ["", "after"])
    }

    // MARK: Code blocks (Raycast's own code block extension)

    @Test func `enter in a code block always adds a line`() {
        type("```\nlet a\n\n\nout")
        #expect(kinds == [.code, .code, .code, .code, .paragraph])
        #expect(texts == ["let a", "", "", "out", ""])
    }

    @Test func `a fence with a language makes a code block on space or enter`() {
        type("```swift let a")
        #expect(editor.blocks[0] == Block(kind: .code, language: "swift", runs: [Run(text: "let a")]))
        editor.load([Block(kind: .paragraph)], caret: 0)
        type("~~~c++\nint")
        #expect(editor.blocks[0] == Block(kind: .code, language: "c++", runs: [Run(text: "int")]))
        editor.load([Block(kind: .paragraph)], caret: 0)
        type("```Swift ")
        #expect(kinds == [.paragraph], "languages are lowercase only, like the input rule's regex")
    }

    @Test func `a code block at the end keeps a paragraph after it`() {
        type("```\ncode")
        #expect(kinds == [.code, .paragraph])
    }

    @Test func `shift enter and command enter leave a code block`() {
        type("```\na")
        command(#selector(NSResponder.insertLineBreak(_:)))
        type("b")
        #expect(kinds == [.code, .paragraph, .paragraph])
        #expect(texts == ["a", "b", ""])
        editor.textView.setSelectedRange(NSRange(location: 0, length: 0))
        editor.toggleTask()
        #expect(kinds == [.code, .paragraph, .paragraph, .paragraph])
    }

    @Test func `backspace at the start of a code line joins it to the line above`() {
        type("```\nab\ncd")
        editor.textView.setSelectedRange(NSRange(location: 3, length: 0))
        backspace()
        #expect(kinds == [.code, .paragraph])
        #expect(texts == ["abcd", ""])
    }

    @Test func `backspace in an empty code block turns it into a paragraph`() {
        type("```\n")
        #expect(kinds == [.code, .paragraph])
        editor.textView.setSelectedRange(NSRange(location: 0, length: 0))
        backspace()
        #expect(kinds == [.paragraph, .paragraph])
    }

    @Test func `backspace at the start of a code block joins it into the text above`() {
        type("intro\n```\na\nb")
        editor.textView.setSelectedRange(NSRange(location: 6, length: 0))
        backspace()
        #expect(kinds == [.paragraph, .paragraph])
        #expect(texts == ["introa b", ""])
    }

    @Test func `tab inserts a tab in code and shift tab removes it`() {
        type("```\nx")
        editor.textView.setSelectedRange(NSRange(location: 0, length: 0))
        command(#selector(NSResponder.insertTab(_:)))
        #expect(texts[0] == "\tx")
        command(#selector(NSResponder.insertBacktab(_:)))
        #expect(texts[0] == "x")
        type("  ")
        command(#selector(NSResponder.insertBacktab(_:)))
        #expect(texts[0] == "x")
    }

    @Test func `select all inside a code block selects the block first`() {
        type("intro\n```\nab\ncd")
        editor.textView.selectAll(nil)
        #expect(editor.textView.selectedRange() == NSRange(location: 6, length: 5))
        editor.textView.selectAll(nil)
        #expect(editor.textView.selectedRange() == NSRange(location: 0, length: editor.text.utf16.count))
    }

    @Test func `marks don't apply inside a code block`() {
        type("```\nx")
        editor.toggleMark(.bold)
        type("y")
        #expect(editor.blocks[0].runs == [Run(text: "xy")])
    }

    // MARK: Copy & paste

    @Test func `copying inside a code block copies the code as it is`() {
        type("```\nlet a\nlet b")
        editor.textView.setSelectedRange(NSRange(location: 0, length: 11))
        let board = pasteboard()
        _ = editor.textView.writeSelection(to: board, type: .string)
        #expect(board.string(forType: .string) == "let a\nlet b")
    }

    @Test func `copying across blocks writes Raycast's markdown text and skips empty blocks`() {
        type("# T\n\n- a\nb\n\n```js\nx")
        editor.textView.selectAll(nil)
        editor.textView.selectAll(nil)
        let board = pasteboard()
        _ = editor.textView.writeSelection(to: board, type: .string)
        #expect(board.string(forType: .string) == "# T\n\n- a\n- b\n\n```js\nx\n```")
    }

    @Test func `pasted plain text is read as markdown with line breaks`() {
        paste("one\ntwo\n\n- item\n\n```py\nx = 1\n\ny\n```")
        #expect(kinds == [.paragraph, .bullet, .code, .code, .code, .paragraph])
        #expect(texts == ["one\u{2028}two", "item", "x = 1", "", "y", ""])
        #expect(editor.blocks[2].language == "py")
    }

    @Test func `pasting into a code block inserts the text with its newlines`() {
        type("```\n")
        paste("a\n\n- b")
        #expect(kinds == [.code, .code, .code, .paragraph])
        #expect(texts == ["a", "", "- b", ""])
    }

    @Test func `pasting one line goes inline and keeps the block type`() {
        type("# ab")
        editor.textView.setSelectedRange(NSRange(location: 1, length: 0))
        paste("**x**")
        #expect(editor.blocks[0].kind == .heading1)
        #expect(editor.blocks[0].runs == [Run(text: "a"), Run(text: "x", marks: .bold), Run(text: "b")])
    }

    // MARK: Images

    private let photo = ImageRef(attachmentId: "01PHOTO", width: 800, height: 600)

    @Test func `an image goes into an empty paragraph with the caret below it`() {
        editor.insertImageBlocksAtSelection([photo])
        #expect(kinds == [.image, .paragraph])
        #expect(editor.blocks[0].image == photo)
        #expect(editor.textView.selectedRange() == NSRange(location: 2, length: 0))
    }

    @Test func `an image splits the paragraph at the caret`() {
        type("abcd")
        editor.textView.setSelectedRange(NSRange(location: 2, length: 0))
        editor.insertImageBlocksAtSelection([photo])
        #expect(kinds == [.paragraph, .image, .paragraph])
        #expect(texts == ["ab", "", "cd"])
    }

    @Test func `backspace after an image selects it, and again deletes it`() {
        editor.load([.paragraph("above"), .image(photo), .paragraph("below")], caret: 0)
        editor.textView.setSelectedRange(NSRange(location: 8, length: 0))
        backspace()
        #expect(editor.selectedImage?.ref == photo)
        backspace()
        #expect(kinds == [.paragraph, .paragraph])
        #expect(texts == ["above", "below"])
    }

    @Test func `a caret landing on an image selects it, and arrows leave it`() {
        editor.load([.paragraph("above"), .image(photo), .paragraph("below")], caret: 0)
        editor.textView.setSelectedRange(NSRange(location: 6, length: 0))
        #expect(editor.selectedImage?.ref == photo)
        command(#selector(NSResponder.moveDown(_:)))
        #expect(editor.textView.selectedRange() == NSRange(location: 8, length: 0))
    }

    @Test func `typing over a selected image replaces it with text`() {
        editor.load([.image(photo), .paragraph("")], caret: 0)
        editor.textView.setSelectedRange(NSRange(location: 0, length: 1))
        type("x")
        #expect(kinds.first == .paragraph)
        #expect(texts.first == "x")
    }

    @Test func `copying a selected image and pasting it keeps the same file`() {
        editor.load([.image(photo), .paragraph("")], caret: 0)
        let board = pasteboard()
        board.setString(TiptapCodec.encodeString([.image(photo)]), forType: .jotBlocks)
        editor.textView.setSelectedRange(NSRange(location: 2, length: 0))
        _ = editor.paste(from: board)
        #expect(editor.blocks.compactMap(\.image) == [photo, photo])
    }

    @Test func `a pasted screenshot becomes an image block with its file stored`() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        editor.attachments = AttachmentStore(directory: directory)
        #expect(editor.textView.readablePasteboardTypes.contains(.png))

        let board = pasteboard()
        board.setData(ImageTests.image(width: 120, height: 80), forType: .png)
        #expect(editor.paste(from: board))
        for _ in 0..<100 where editor.blocks.first?.kind != .image {
            try await Task.sleep(for: .milliseconds(20))
        }
        let image = try #require(editor.blocks.first?.image)
        #expect(image.width == 120 && image.height == 80)
        #expect(editor.attachments?.url(for: image.attachmentId) != nil)
        #expect(kinds == [.image, .paragraph])
    }

    @Test func `enter on a heading continues with body text`() {
        type("# Title\nbody")
        #expect(kinds == [.heading1, .paragraph, .paragraph])
    }

    @Test func `toggle mark over a selection`() {
        type("hello world")
        editor.textView.setSelectedRange(NSRange(location: 0, length: 5))
        editor.toggleMark(.bold)
        #expect(editor.blocks[0].runs == [Run(text: "hello", marks: .bold), Run(text: " world")])
        editor.toggleMark(.bold)
        #expect(editor.blocks[0].runs == [Run(text: "hello world")])
    }

    @Test func `toggle block applies to every selected paragraph`() {
        type("a\nb")
        editor.textView.setSelectedRange(NSRange(location: 0, length: 3))
        editor.toggleBlock(.task)
        #expect(kinds == [.task, .task, .paragraph])
        editor.toggleTask()
        #expect(editor.blocks.map(\.checked) == [true, true, false])
    }

    @Test func `round-trips through load`() {
        let blocks = WelcomeNote.showcase
        editor.load(blocks, caret: 0)
        #expect(editor.blocks == blocks)
    }
}

/// Raycast's "/" menu: when it opens, how it filters, and what choosing does.
@MainActor
struct SlashMenuTests {
    let editor = NoteEditor()
    private var menu: SlashMenu { editor.slashMenu }
    private var titles: [String] { menu.model.filteredSections.flatMap(\.items).map(\.title) }

    private func type(_ text: String) {
        for character in text {
            editor.textView.insertText(String(character), replacementRange: editor.textView.selectedRange())
        }
    }

    private func command(_ selector: Selector) {
        editor.textView.doCommand(by: selector)
    }

    @Test func `slash at the start of a line or after a space opens the menu`() {
        type("/")
        #expect(menu.isVisible)
        #expect(menu.model.filteredSections.map(\.title) == ["Headings", "Inline", "Blocks", "Lists"])
        editor.load([Block(kind: .paragraph)], caret: 0)
        type("a/")
        #expect(!menu.isVisible)
        type(" /")
        #expect(menu.isVisible)
    }

    @Test func `a leading space or a double space closes it`() {
        type("/ ")
        #expect(!menu.isVisible)
        editor.load([Block(kind: .paragraph)], caret: 0)
        type("/heading 1")
        #expect(menu.isVisible)
        #expect(titles.first == "Heading 1")
        type("  ")
        #expect(!menu.isVisible)
    }

    @Test func `a query flattens the sections into ranked results`() {
        type("/co")
        #expect(menu.model.filteredSections.count == 1)
        #expect(menu.model.filteredSections[0].title == nil)
        #expect(titles == ["Code", "Code Block"])
        type("x")
        #expect(!menu.isVisible)
    }

    @Test func `keywords find task list`() {
        type("/todo")
        #expect(titles == ["Task List"])
        command(#selector(NSResponder.insertNewline(_:)))
        // The empty paragraph after it is Tiptap's trailing node.
        #expect(editor.blocks.map(\.kind) == [.task, .paragraph])
        #expect(editor.blocks.map(\.text) == ["", ""])
        #expect(!menu.isVisible)
    }

    @Test func `choosing a heading removes the query and keeps the text before it`() {
        type("Title /h2")
        #expect(titles.first == "Heading 2")
        command(#selector(NSResponder.insertNewline(_:)))
        #expect(editor.blocks.map(\.kind) == [.heading2, .paragraph])
        #expect(editor.blocks.map(\.text) == ["Title ", ""])
    }

    @Test func `arrows move without wrapping`() {
        type("/")
        #expect(menu.model.selectedItem?.title == "Heading 1")
        command(#selector(NSResponder.moveUp(_:)))
        #expect(menu.model.selectedItem?.title == "Heading 1")
        command(#selector(NSResponder.moveDown(_:)))
        command(#selector(NSResponder.moveDown(_:)))
        #expect(menu.model.selectedItem?.title == "Heading 3")
        menu.model.moveSection(1)
        #expect(menu.model.selectedItem?.title == "Bold")
    }

    @Test func `an inline mark applies to what's typed next`() {
        type("/bold")
        command(#selector(NSResponder.insertNewline(_:)))
        type("x")
        #expect(editor.blocks.first?.text == "x")
        #expect(editor.blocks.first?.runs.first?.marks.contains(.bold) == true)
    }

    @Test func `escape keeps it closed until the slash is retyped`() {
        type("/he")
        command(#selector(NSResponder.cancelOperation(_:)))
        #expect(!menu.isVisible)
        type("a")
        #expect(!menu.isVisible)
        for _ in 0..<4 { command(#selector(NSResponder.deleteBackward(_:))) }
        type("/")
        #expect(menu.isVisible)
    }

    @Test func `no menu inside a code block`() {
        editor.load([Block(kind: .code)], caret: 0)
        type("/")
        #expect(!menu.isVisible)
    }

    @Test func `the matcher wants word starts`() {
        #expect(MenuSearch.score("Code Block", query: "d").isMatch(queryLength: 1) == false)
        #expect(MenuSearch.score("Code Block", query: "cb").isMatch(queryLength: 2))
        #expect(MenuSearch.score("Bullet List", query: "bullet list") == .exact)
    }
}
