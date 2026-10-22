import AppKit

/// Raycast's notes slash menu (`im` + `rm` on its `At` suggestion plugin): "/" at the start of
/// a paragraph or after a space opens Headings / Inline / Blocks / Lists, filtered by the text
/// typed after it. Choosing a command deletes "/query" and runs it. The query stays in the
/// editor, so the editor keeps focus and forwards the menu's keys.
final class SlashMenu {
    /// The "/" and the query after it, in storage coordinates.
    struct Match: Equatable {
        var range: NSRange
        var query: String
    }

    private unowned let editor: NoteEditor
    let model: MenuModel
    /// The active suggestion's range, whether or not the menu has rows to show. While
    /// there is one, Escape belongs to the menu.
    private(set) var match: Match?
    /// `onVisibilityChange` (the store's `isSlashSuggestionActive`): the window holds its
    /// height while the menu shows.
    var onVisibilityChange: (() -> Void)?
    private var wasVisible = false
    /// The panel is placed once per session (`range.from`), like the popover's reference.
    private var placedFrom: Int?
    /// Where Escape (or a click outside) closed the menu. It stays closed while the match
    /// still starts there (`shouldKeepDismissed` with `allowSpaces`).
    private var dismissedFrom: Int?
    private var panel: SlashMenuPanel?

    init(editor: NoteEditor) {
        self.editor = editor
        model = MenuModel(page: MenuPage(placeholder: "", sections: []))
        model.page = page
        model.wraps = false
        model.onActivate = { [weak self] item in self?.choose(item) }
    }

    /// Whether the menu is on screen and taking its keys (`h(items) && clientRect`).
    /// `getSuggestions` is empty in a code block or inline code, so it hides there.
    var isVisible: Bool {
        match != nil && !model.selectableItems.isEmpty && !editor.isInCodeBlock
            && !Marks(rawValue: editor.textView.typingAttributes[.jotMarks] as? Int ?? 0).contains(.code)
    }

    // MARK: Items

    /// `rm()`: the sections and titles of Raycast's slash menu.
    private var page: MenuPage {
        func item(_ id: String, _ title: String, _ icon: String, keywords: [String] = [], _ run: @escaping (NoteEditor) -> Void) -> MenuItem {
            MenuItem(id: id, title: title, icon: icon, keywords: keywords) { [unowned editor] in run(editor) }
        }
        var page = MenuPage(placeholder: "", sections: [
            MenuSection(id: "headings", title: "Headings", items: [
                item("heading1", "Heading 1", "heading") { $0.toggleBlock(.heading1) },
                item("heading2", "Heading 2", "heading") { $0.toggleBlock(.heading2) },
                item("heading3", "Heading 3", "heading") { $0.toggleBlock(.heading3) },
            ]),
            MenuSection(id: "inline", title: "Inline", items: [
                item("bold", "Bold", "bold") { $0.toggleMark(.bold) },
                item("italic", "Italic", "italics") { $0.toggleMark(.italic) },
                item("strikethrough", "Strikethrough", "strike-through") { $0.toggleMark(.strike) },
                item("underline", "Underline", "underline") { $0.toggleMark(.underline) },
                item("code", "Code", "code") { $0.toggleMark(.code) },
            ]),
            MenuSection(id: "block", title: "Blocks", items: [
                item("codeBlock", "Code Block", "code-block") { $0.toggleBlock(.code) },
                item("blockquote", "Blockquote", "quote-block") { $0.toggleBlock(.quote) },
            ]),
            MenuSection(id: "list", title: "Lists", items: [
                item("orderedList", "Ordered List", "number-list") { $0.toggleBlock(.ordered) },
                item("bulletList", "Bullet List", "bullet-points") { $0.toggleBlock(.bullet) },
                item("taskList", "Task List", "check-list", keywords: ["todo", "check"]) { $0.toggleBlock(.task) },
            ]),
        ], separators: true)
        page.rankedSearch = true
        return page
    }

    // MARK: Matching

    /// Tiptap's `findSuggestionMatch` for "/" with `allowSpaces`, plus `At`'s `allow`:
    /// the text before "/" is empty or ends in a space, the query doesn't start with one
    /// (`dismissOnLeadingSpace`), and no run of spaces is longer than one (`allowSpaces: 1`).
    static func find(in storage: NSAttributedString, caret: Int) -> (match: Match, isAllowed: Bool)? {
        let string = storage.string as NSString
        guard caret > 0, caret <= string.length else { return nil }
        // `$position.nodeBefore`: the text run before the caret with the same marks, inside
        // this paragraph and after any hard break.
        let marks = storage.attribute(.jotMarks, at: caret - 1, effectiveRange: nil) as? Int
        let href = storage.attribute(.jotHref, at: caret - 1, effectiveRange: nil) as? String
        var start = caret
        while start > 0 {
            let character = string.character(at: start - 1)
            if character == 0x0A || character == 0x2028 || character == 0xFFFC { break }
            if storage.attribute(.jotMarks, at: start - 1, effectiveRange: nil) as? Int != marks
                || storage.attribute(.jotHref, at: start - 1, effectiveRange: nil) as? String != href { break }
            start -= 1
        }
        guard start < caret else { return nil }
        let text = string.substring(with: NSRange(location: start, length: caret - start)) as NSString
        guard let found = suggestion.matches(in: text as String, range: NSRange(location: 0, length: text.length)).last else { return nil }

        let from = start + found.range.location
        var to = from + found.range.length
        let tail = NSRange(location: found.range.upperBound - 1, length: min(2, text.length - found.range.upperBound + 1))
        if tail.location >= 0, text.substring(with: tail).range(of: #"\s/$"#, options: .regularExpression) != nil { to += 1 }
        guard from < caret, to >= caret else { return nil }

        let query = string.substring(with: NSRange(location: from + 1, length: to - from - 1))
        let match = Match(range: NSRange(location: from, length: to - from), query: query)
        let before: unichar? = from > 0 ? string.character(at: from - 1) : nil
        let afterSpace = before == nil || before == 0x0A || before == 0x2028 || before == 0x20 || before == 0xA0
        let leadingSpace = query.hasPrefix(" ") || query.hasPrefix("\u{00A0}")
        let longSpaces = query.range(of: "  ") != nil
        return (match, afterSpace && !leadingSpace && !longSpaces)
    }

    private static let suggestion = try! NSRegularExpression(pattern: #"/.*?(?=\s/|$)"#, options: [.anchorsMatchLines])

    /// The suggestion plugin's `apply`, run after every edit and selection change.
    func update() {
        let selection = editor.textView.selectedRange()
        var next: Match?
        if editor.textView.isEditable, selection.length == 0 {
            if let (found, isAllowed) = Self.find(in: editor.storage, caret: selection.location) {
                if isAllowed {
                    if let dismissed = dismissedFrom, dismissed != found.range.location { dismissedFrom = nil }
                    if dismissedFrom == nil { next = found }
                }
            } else {
                dismissedFrom = nil
            }
        }
        let query = next?.query ?? ""
        match = next
        // Every query change selects the first result again.
        if query != model.query || model.selectedItem == nil {
            model.query = query
            model.selectFirst()
        }
        render()
    }

    /// Keeps the dismissed position on its "/" as text is edited before it (`mapping.map`).
    func map(edited: NSRange, changeInLength delta: Int) {
        guard let dismissed = dismissedFrom else { return }
        let originalEnd = edited.location + edited.length - delta
        if dismissed >= originalEnd { dismissedFrom = dismissed + delta }
        else if dismissed > edited.location { dismissedFrom = NSMaxRange(edited) }
    }

    /// Escape, or a click outside: closes the menu until the trigger is retyped.
    func dismiss() {
        guard let match else { return }
        dismissedFrom = match.range.location
        self.match = nil
        render()
    }

    /// Note loads and window changes: forget everything.
    func reset() {
        match = nil
        dismissedFrom = nil
        render()
    }

    // MARK: Keys

    /// The menu's `onKeyDown` while it shows: ↑ ↓ move (⌥ by five, ⌘ by section, no
    /// wrapping), ⌘1–9 and ⌘0 choose the Nth row, Return chooses, Tab does nothing.
    /// Escape closes the suggestion even when nothing shows. `false` passes the key on.
    func handleKey(_ event: NSEvent) -> Bool {
        guard match != nil else { return false }
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        if event.keyCode == 53, flags.isEmpty {
            dismiss()
            return true
        }
        guard isVisible else { return false }
        switch event.keyCode {
        case 125, 126:
            let delta = event.keyCode == 125 ? 1 : -1
            if flags == .command { model.moveSection(delta) }
            else if flags == .option { model.move(delta * 5) }
            else if flags.isEmpty { model.move(delta) }
            else { return false }
        case 36, 76:
            guard flags.isEmpty else { return false }
            if let item = model.selectedItem { choose(item) }
        case 48:
            guard flags.subtracting(.shift).isEmpty else { return false }
        case 116, 121:
            model.move(event.keyCode == 121 ? 7 : -7)
        default:
            guard flags == .command, let digit = event.charactersIgnoringModifiers.flatMap(Int.init), (0...9).contains(digit) else { return false }
            let items = model.selectableItems
            let index = digit == 0 ? 9 : digit - 1
            guard index < items.count else { return true }
            model.selectedID = items[index].id
            choose(items[index])
        }
        return true
    }

    /// Commands that arrive without a key event of their own (⌃N / ⌃P move too).
    func handle(_ selector: Selector) -> Bool? {
        guard match != nil else { return nil }
        switch selector {
        case #selector(NSResponder.cancelOperation(_:)): dismiss()
        case #selector(NSResponder.moveDown(_:)) where isVisible: model.move(1)
        case #selector(NSResponder.moveUp(_:)) where isVisible: model.move(-1)
        case #selector(NSResponder.insertNewline(_:)) where isVisible:
            if let item = model.selectedItem { choose(item) }
        default: return nil
        }
        return true
    }

    private func choose(_ item: MenuItem) {
        guard let match, NSMaxRange(match.range) <= editor.storage.length else { return }
        self.match = nil
        render()
        editor.grouped {
            editor.textView.setSelectedRange(match.range)
            editor.replace(match.range, with: "", attributes: [:])
            editor.textView.setSelectedRange(NSRange(location: match.range.location, length: 0))
            item.action()
        }
        editor.focus()
    }

    // MARK: Panel

    private func render() {
        let visible = isVisible
        defer {
            if visible != wasVisible {
                wasVisible = visible
                onVisibilityChange?()
            }
        }
        guard visible, let match, let window = editor.textView.window else {
            panel?.close()
            placedFrom = nil
            return
        }
        let panel = self.panel ?? SlashMenuPanel(model: model)
        self.panel = panel
        panel.onOutsideClick = { [weak self] in self?.dismiss() }
        if placedFrom != match.range.location || !panel.isVisible {
            placedFrom = match.range.location
            panel.show(anchor: anchorRect(for: match.range), in: window)
        } else {
            panel.fitHeight()
        }
    }

    /// The "/query" decoration's rect in screen coordinates (`clientRect`).
    private func anchorRect(for range: NSRange) -> NSRect {
        var actual = NSRange()
        return editor.textView.firstRect(forCharacterRange: range, actualRange: &actual)
    }
}
