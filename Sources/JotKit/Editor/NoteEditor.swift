import AppKit

/// What the format bar needs to show as active.
struct EditorState: Equatable {
    var marks: Marks = []
    var block: BlockKind = .paragraph
    var hasLink = false
}

/// Owns the TextKit 2 stack and implements Raycast Notes' editing behaviour:
/// markdown input rules, list/heading/code Enter & Backspace semantics, marks,
/// checkboxes, links, find highlights, and zoom.
final class NoteEditor: NSObject {
    let scrollView = NSScrollView()
    let textView: NoteTextView
    let contentStorage = NSTextContentStorage()
    let layoutManager = NSTextLayoutManager()
    private let placeholder = NSTextField(labelWithString: "Write something …")

    var style = EditorStyle() {
        didSet { if style.zoom != oldValue.zoom { applyZoom() } }
    }

    /// Top and bottom padding inside the scroll view (clears the glass header and footer).
    var verticalInset: CGFloat = Layout.editorVerticalPadding {
        didSet {
            textView.textContainerInset = NSSize(width: Layout.editorHorizontalPadding, height: verticalInset)
            updatePlaceholder()
        }
    }

    var onChange: (() -> Void)?
    var onSelectionChange: (() -> Void)?
    var onLayout: (() -> Void)?
    /// A toast: title, optional message, and whether it reports a failure.
    var onToast: ((String, String?, Bool) -> Void)?

    /// Where image files live (next to the database).
    var attachments: AttachmentStore?

    var restyler: Restyler { Restyler(style: style) }
    var storage: NSTextStorage { contentStorage.textStorage! }
    private var isLoading = false
    private var lastCaret = 0
    private(set) lazy var slashMenu = SlashMenu(editor: self)

    override init() {
        contentStorage.addTextLayoutManager(layoutManager)
        let container = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        container.lineFragmentPadding = 0
        layoutManager.textContainer = container
        textView = NoteTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 200), textContainer: container)
        super.init()

        textView.editor = self
        textView.delegate = self
        layoutManager.delegate = self
        storage.delegate = self

        textView.isRichText = true
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.usesFindBar = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = true
        textView.isAutomaticQuoteSubstitutionEnabled = true
        textView.isContinuousSpellCheckingEnabled = false
        textView.smartInsertDeleteEnabled = false
        textView.insertionPointColor = Theme.accent
        textView.selectedTextAttributes = [.backgroundColor: Theme.selection]
        textView.textContainerInset = NSSize(width: Layout.editorHorizontalPadding, height: Layout.editorVerticalPadding)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)

        scrollView.documentView = textView
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.contentInsets = NSEdgeInsets()
        // The clip view adds its own automatic 16pt top/bottom insets; the editor's
        // padding is already exact (header 52 + 4), so turn them off.
        scrollView.contentView.automaticallyAdjustsContentInsets = false
        scrollView.contentView.contentInsets = NSEdgeInsets()

        textView.registerForDraggedTypes([.fileURL, .jotImageMove])
        NotificationCenter.default.addObserver(self, selector: #selector(imageDecoded(_:)), name: .jotImageDecoded, object: nil)

        placeholder.textColor = Theme.textTertiary
        placeholder.isSelectable = false
        textView.addSubview(placeholder)

        load([Block(kind: .paragraph)], caret: 0)
    }

    // MARK: Loading & reading

    func load(_ blocks: [Block], caret: Int) {
        isLoading = true
        storage.setAttributedString(DocumentCodec.attributedString(blocks))
        ensureTrailingParagraph()
        restyler.restyle(storage)
        updateFirstBlockSpacing()
        isLoading = false
        textView.undoManager?.removeAllActions()
        let location = min(max(0, caret), max(0, storage.length - 1))
        textView.setSelectedRange(NSRange(location: location, length: 0))
        updateTypingAttributes()
        updatePlaceholder()
        textView.scrollRangeToVisible(textView.selectedRange())
        slashMenu.reset()
    }

    var blocks: [Block] { DocumentCodec.blocks(storage) }

    /// The selected blocks, or nil when nothing is selected ("Copy Selection As…").
    var selectedBlocks: [Block]? {
        let selection = textView.selectedRange()
        return selection.length > 0 ? DocumentCodec.blocks(storage, in: selection) : nil
    }
    var caret: Int { textView.selectedRange().location }
    var plainText: String { blocks.plainText }

    /// Raycast: grapheme count of the trimmed plain text (`Intl.Segmenter`, granularity grapheme).
    var characterCount: Int { plainText.trimmingCharacters(in: .whitespacesAndNewlines).count }

    /// Raycast: word-like segments of the trimmed plain text.
    var wordCount: Int {
        let text = plainText.trimmingCharacters(in: .whitespacesAndNewlines)
        var count = 0
        text.enumerateSubstrings(in: text.startIndex..., options: [.byWords, .substringNotRequired]) { _, _, _, _ in count += 1 }
        return count
    }

    var state: EditorState {
        let caret = max(0, min(textView.selectedRange().location, storage.length - 1))
        let info = storage.paragraphInfo(at: paragraphRange(at: caret))
        let marks = Marks(rawValue: textView.typingAttributes[.jotMarks] as? Int ?? 0)
        let hasLink = textView.typingAttributes[.jotHref] != nil
            || (caret < storage.length && storage.attribute(.jotHref, at: caret, effectiveRange: nil) != nil)
        return EditorState(marks: marks, block: info.kind, hasLink: hasLink)
    }

    /// Height the text needs, excluding the trailing newline's empty line.
    var contentHeight: CGFloat {
        layoutManager.ensureLayout(for: contentStorage.documentRange)
        var bottom: CGFloat = 0
        layoutManager.enumerateTextLayoutFragments(from: contentStorage.documentRange.endLocation, options: [.reverse, .ensuresLayout]) { fragment in
            let frame = fragment.layoutFragmentFrame
            let lines = fragment.textLineFragments
            if let line = lines.last(where: { $0.characterRange.length > 0 }) ?? lines.first {
                bottom = frame.minY + line.typographicBounds.maxY
            } else {
                bottom = frame.maxY
            }
            return false
        }
        if bottom == 0 { bottom = layoutManager.usageBoundsForTextContainer.height }
        return bottom + textView.textContainerInset.height * 2 + textView.firstBlockSpacing
    }

    func focus() {
        textView.window?.makeFirstResponder(textView)
    }

    // MARK: Paragraph helpers

    func paragraphRange(at index: Int) -> NSRange {
        let string = storage.string as NSString
        return string.paragraphRange(for: NSRange(location: min(max(0, index), string.length), length: 0))
    }

    func contentRange(_ paragraph: NSRange) -> NSRange {
        let string = storage.string as NSString
        if paragraph.length > 0, string.character(at: NSMaxRange(paragraph) - 1) == 0x0A {
            return NSRange(location: paragraph.location, length: paragraph.length - 1)
        }
        return paragraph
    }

    func info(at index: Int) -> ParagraphInfo {
        storage.paragraphInfo(at: paragraphRange(at: index))
    }

    private func selectedParagraphs() -> [NSRange] {
        let selection = textView.selectedRange()
        let string = storage.string as NSString
        let union = string.paragraphRange(for: NSRange(location: min(selection.location, string.length), length: selection.length))
        return storage.attributedSubstring(from: union).paragraphRanges.map {
            NSRange(location: $0.location + union.location, length: $0.length)
        }
    }

    /// The paragraph's text before `caret`.
    private func prefix(at caret: Int) -> String {
        let paragraph = paragraphRange(at: caret)
        return (storage.string as NSString).substring(with: NSRange(location: paragraph.location, length: caret - paragraph.location))
    }

    /// The code block around `index`: all its lines, including the last one's newline.
    private func codeGroup(at index: Int) -> NSRange {
        var group = paragraphRange(at: index)
        while group.location > 0, info(at: group.location - 1).kind == .code {
            group = NSUnionRange(group, paragraphRange(at: group.location - 1))
        }
        while NSMaxRange(group) < storage.length, info(at: NSMaxRange(group)).kind == .code {
            group = NSUnionRange(group, paragraphRange(at: NSMaxRange(group)))
        }
        return group
    }

    struct CodeFence: Equatable {
        var language: String?
    }

    /// Raycast's code block input rules: `/^```([a-z+#-]*)[\s\n]$/` and the `~~~` form.
    static func codeFence(_ prefix: String) -> CodeFence? {
        guard let match = prefix.wholeMatch(of: /(?:```|~~~)([a-z+#-]*)/) else { return nil }
        return CodeFence(language: match.1.isEmpty ? nil : String(match.1))
    }

    /// Turns the paragraph into a code block, dropping the fence typed at its start.
    private func convertToCode(_ paragraph: NSRange, removing length: Int, language: String?) {
        grouped {
            replace(NSRange(location: paragraph.location, length: length), with: "", attributes: [:])
            setInfo(ParagraphInfo(kind: .code, language: language), at: paragraph.location)
        }
        textView.setSelectedRange(NSRange(location: paragraph.location, length: 0))
        updateTypingAttributes()
    }

    /// ProseMirror's `exitCode`: a new paragraph after the code block, with the caret in it.
    private func exitCodeBlock() {
        let group = codeGroup(at: textView.selectedRange().location)
        split(at: NSMaxRange(group) - 1, next: ParagraphInfo())
    }

    /// Tiptap's trailing node: the document always ends with a paragraph, so there is
    /// somewhere to type after a final code block, list, heading or quote.
    private func ensureTrailingParagraph() {
        guard commandDepth == 0, storage.length > 0, info(at: storage.length - 1).kind != .paragraph else { return }
        let end = NSRange(location: storage.length, length: 0)
        let newline = NSAttributedString(string: "\n", attributes: paragraphAttributes(ParagraphInfo()))
        if isLoading {
            storage.append(newline)
            return
        }
        let selection = textView.selectedRange()
        guard textView.shouldChangeText(in: end, replacementString: newline.string) else { return }
        storage.replaceCharacters(in: end, with: newline)
        textView.didChangeText()
        textView.setSelectedRange(selection)
    }

    /// ⌘A inside a code block selects the block; pressed again, the whole note.
    func handleSelectAll() -> Bool {
        let selection = textView.selectedRange()
        guard storage.length > 0, info(at: selection.location).kind == .code else { return false }
        let group = codeGroup(at: selection.location)
        let content = NSRange(location: group.location, length: group.length - 1)
        guard selection != content else { return false }
        textView.setSelectedRange(content)
        return true
    }

    var isInCodeBlock: Bool { storage.length > 0 && info(at: textView.selectedRange().location).kind == .code }

    // MARK: Undoable primitives

    /// Nesting depth of `grouped`; the trailing paragraph is checked once the outermost
    /// command finishes (ProseMirror's `appendTransaction`), not between its steps.
    private var commandDepth = 0

    func grouped(_ body: () -> Void) {
        textView.breakUndoCoalescing()
        textView.undoManager?.beginUndoGrouping()
        commandDepth += 1
        body()
        commandDepth -= 1
        if commandDepth == 0 { ensureTrailingParagraph() }
        textView.undoManager?.endUndoGrouping()
    }

    func replace(_ range: NSRange, with string: NSAttributedString) {
        guard textView.shouldChangeText(in: range, replacementString: string.string) else { return }
        storage.replaceCharacters(in: range, with: string)
        textView.didChangeText()
    }

    func replace(_ range: NSRange, with string: String, attributes: [NSAttributedString.Key: Any]) {
        replace(range, with: NSAttributedString(string: string, attributes: attributes))
    }

    func setInfo(_ info: ParagraphInfo, for paragraphs: [NSRange]) {
        let targets = paragraphs.filter { $0.length > 0 }
        guard let first = targets.first, let last = targets.last else { return }
        let union = NSUnionRange(first, last)
        guard textView.shouldChangeText(in: union, replacementString: nil) else { return }
        for range in targets { storage.addAttributes(info.attributes, range: range) }
        textView.didChangeText()
        updateTypingAttributes()
    }

    func setInfo(_ info: ParagraphInfo, at index: Int) {
        setInfo(info, for: [paragraphRange(at: index)])
    }

    func paragraphAttributes(_ info: ParagraphInfo) -> [NSAttributedString.Key: Any] {
        restyler.typingAttributes(info: info, marks: [], href: nil, paragraphStyle: restyler.makeParagraphStyle(info))
    }

    // MARK: Typing attributes & caret

    func updateTypingAttributes() {
        let selection = textView.selectedRange()
        let index = min(selection.location, max(0, storage.length - 1))
        let paragraph = paragraphRange(at: index)
        let info = storage.paragraphInfo(at: paragraph)
        var marks: Marks = []
        var href: String?
        let previous = selection.location - 1
        if previous >= paragraph.location, previous < storage.length, (storage.string as NSString).character(at: previous) != 0x0A {
            marks = storage.marks(at: previous)
            href = nil // links aren't inclusive, like Tiptap's
        }
        if info.kind == .code { marks = [] }
        let style = storage.length > 0 ? storage.attribute(.paragraphStyle, at: index, effectiveRange: nil) as? NSParagraphStyle : nil
        textView.typingAttributes = restyler.typingAttributes(info: info, marks: marks, href: href, paragraphStyle: style)
    }

    private func updateFirstBlockSpacing() {
        let style = storage.length > 0 ? storage.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle : nil
        textView.firstBlockSpacing = style?.paragraphSpacingBefore ?? 0
    }

    private func updatePlaceholder() {
        let isEmpty = storage.length <= 1 && info(at: 0).kind == .paragraph
        placeholder.isHidden = !isEmpty
        placeholder.font = Fonts.inter(size: style.fontSize(.paragraph))
        placeholder.sizeToFit()
        let lineHeight = style.lineHeight(.paragraph)
        placeholder.setFrameOrigin(NSPoint(
            x: textView.textContainerInset.width,
            y: textView.textContainerInset.height + style.px(8) + ((lineHeight - placeholder.frame.height) / 2).rounded()
        ))
    }

    /// Keeps the caret off the trailing empty line and out of horizontal rules.
    private func normalizeSelection() {
        let selection = textView.selectedRange()
        guard selection.length == 0, storage.length > 0 else { lastCaret = selection.location; return }
        var caret = selection.location
        if caret >= storage.length { caret = storage.length - 1 }
        // A caret on an image's line selects the image, like ProseMirror's NodeSelection.
        if info(at: caret).kind == .image {
            let paragraph = paragraphRange(at: caret)
            if contentRange(paragraph).length == 1 {
                textView.setSelectedRange(NSRange(location: paragraph.location, length: 1))
                lastCaret = paragraph.location
                return
            }
        }
        if info(at: caret).kind == .rule {
            let paragraph = paragraphRange(at: caret)
            caret = caret >= lastCaret ? min(NSMaxRange(paragraph), storage.length - 1) : max(0, paragraph.location - 1)
            if info(at: caret).kind == .rule { caret = NSMaxRange(paragraph) }
        }
        if caret != selection.location {
            textView.setSelectedRange(NSRange(location: min(caret, storage.length - 1), length: 0))
        }
        lastCaret = textView.selectedRange().location
    }

    // MARK: Input rules

    /// Block rules fire on space; returns true when the keystroke was consumed.
    func handleBeforeInsert(_ typed: String) -> Bool {
        if handleTypingOverImage(typed) { return true }
        let selection = textView.selectedRange()
        guard selection.length == 0 else { return false }
        let caret = selection.location
        let paragraph = paragraphRange(at: caret)
        let info = storage.paragraphInfo(at: paragraph)
        let prefix = (storage.string as NSString).substring(with: NSRange(location: paragraph.location, length: caret - paragraph.location))

        if typed == " ", info.kind == .paragraph || info.kind.isHeading, let fence = Self.codeFence(prefix) {
            convertToCode(paragraph, removing: prefix.utf16.count, language: fence.language)
            return true
        }

        if typed == " " {
            var target: ParagraphInfo?
            switch (info.kind, prefix) {
            case (.paragraph, "#"): target = ParagraphInfo(kind: .heading1)
            case (.paragraph, "##"): target = ParagraphInfo(kind: .heading2)
            case (.paragraph, "###"): target = ParagraphInfo(kind: .heading3)
            case (.paragraph, "-"), (.paragraph, "*"), (.paragraph, "+"): target = ParagraphInfo(kind: .bullet)
            case (.ordered, "-"), (.ordered, "*"), (.task, "-"), (.task, "*"):
                target = ParagraphInfo(kind: .bullet, indent: info.indent)
            case (.paragraph, "[]"), (.paragraph, "[ ]"), (.paragraph, "- [ ]"), (.paragraph, "* [ ]"),
                 (.bullet, "[]"), (.bullet, "[ ]"), (.ordered, "[]"), (.ordered, "[ ]"):
                target = ParagraphInfo(kind: .task, indent: info.indent)
            case (.paragraph, "[x]"), (.paragraph, "- [x]"), (.bullet, "[x]"):
                target = ParagraphInfo(kind: .task, indent: info.indent, checked: true)
            case (.paragraph, ">"): target = ParagraphInfo(kind: .quote)
            case (let kind, let p) where (kind == .paragraph || kind.isList) && kind != .ordered
                && p.count <= 4 && p.hasSuffix(".") && Int(p.dropLast()) != nil:
                target = ParagraphInfo(kind: .ordered, indent: info.indent)
            default: break
            }
            if let target {
                grouped {
                    replace(NSRange(location: paragraph.location, length: prefix.utf16.count), with: "", attributes: [:])
                    setInfo(target, at: paragraph.location)
                }
                return true
            }
        }

        // `---` becomes a horizontal rule (Tiptap's input rule fires on the third dash).
        if typed == "-", info.kind == .paragraph, prefix == "--", contentRange(paragraph).length == 2 {
            grouped {
                replace(contentRange(paragraph), with: "", attributes: [:])
                setInfo(ParagraphInfo(kind: .rule), at: paragraph.location)
                replace(NSRange(location: paragraph.location + 1, length: 0), with: "\n", attributes: paragraphAttributes(ParagraphInfo()))
            }
            textView.setSelectedRange(NSRange(location: paragraph.location + 1, length: 0))
            return true
        }
        return false
    }

    /// Inline rules fire after the closing delimiter is typed.
    func handleAfterInsert(_ typed: String) {
        guard ["*", "_", "`", "~"].contains(typed) else { return }
        let caret = textView.selectedRange().location
        let paragraph = paragraphRange(at: caret - 1)
        guard storage.paragraphInfo(at: paragraph).kind != .code else { return }
        let before = (storage.string as NSString).substring(with: NSRange(location: paragraph.location, length: caret - paragraph.location))
        guard let match = InlineRule.match(before) else { return }

        let spanStart = paragraph.location + match.spanOffset
        let span = NSRange(location: spanStart, length: caret - spanStart)
        let innerRange = NSRange(location: spanStart + match.delimiterLength, length: match.innerLength)
        let inner = NSMutableAttributedString(attributedString: storage.attributedSubstring(from: innerRange))
        inner.enumerateAttribute(.jotMarks, in: NSRange(location: 0, length: inner.length)) { value, range, _ in
            let marks = Marks(rawValue: value as? Int ?? 0).union(match.mark)
            inner.addAttribute(.jotMarks, value: marks.rawValue, range: range)
        }
        grouped { replace(span, with: inner) }
        textView.setSelectedRange(NSRange(location: spanStart + inner.length, length: 0))
        var typing = textView.typingAttributes
        let marks = Marks(rawValue: typing[.jotMarks] as? Int ?? 0).subtracting(match.mark)
        typing[.jotMarks] = marks.rawValue
        textView.typingAttributes = restyler.typingAttributes(
            info: info(at: caret - 1), marks: marks, href: nil, paragraphStyle: typing[.paragraphStyle] as? NSParagraphStyle
        )
    }

    // MARK: Key commands

    private func handleEnter() -> Bool {
        if textView.selectedRange().length > 0 { textView.insertText("", replacementRange: textView.selectedRange()) }
        let caret = textView.selectedRange().location
        let paragraph = paragraphRange(at: caret)
        let info = storage.paragraphInfo(at: paragraph)
        let content = contentRange(paragraph)

        // Tiptap runs input rules on Enter too: "```swift⏎" makes a Swift code block.
        if info.kind == .paragraph || info.kind.isHeading, let fence = Self.codeFence(prefix(at: caret)) {
            convertToCode(paragraph, removing: caret - paragraph.location, language: fence.language)
            return true
        }

        switch info.kind {
        case .bullet, .ordered, .task:
            if content.length == 0 {
                let target = info.indent > 0
                    ? ParagraphInfo(kind: info.kind, indent: info.indent - 1)
                    : ParagraphInfo()
                grouped { setInfo(target, at: caret) }
            } else {
                split(at: caret, next: ParagraphInfo(kind: info.kind, indent: info.indent))
            }
        case .heading1, .heading2, .heading3:
            if caret == content.location, content.length > 0 {
                grouped { replace(NSRange(location: caret, length: 0), with: "\n", attributes: paragraphAttributes(ParagraphInfo())) }
            } else {
                split(at: caret, next: ParagraphInfo())
            }
        case .quote:
            if content.length == 0 { grouped { setInfo(ParagraphInfo(), at: caret) } }
            else { split(at: caret, next: info) }
        case .code:
            // Raycast's code block: Enter is always `newlineInCode` (no triple-Enter exit).
            split(at: caret, next: info)
        case .paragraph:
            split(at: caret, next: ParagraphInfo())
        case .rule, .image:
            split(at: NSMaxRange(paragraph), next: ParagraphInfo())
        }
        return true
    }

    /// Inserts a newline at `caret`; the text after it becomes a paragraph with `next`'s block state.
    func split(at caret: Int, next: ParagraphInfo) {
        let current = info(at: caret)
        grouped {
            var attributes = textView.typingAttributes
            attributes.merge(current.attributes) { $1 }
            attributes[.jotMarks] = 0
            attributes[.jotHref] = nil
            replace(NSRange(location: caret, length: 0), with: "\n", attributes: attributes)
            if next != info(at: caret + 1) { setInfo(next, at: caret + 1) }
        }
        textView.setSelectedRange(NSRange(location: caret + 1, length: 0))
        updateTypingAttributes()
        textView.scrollRangeToVisible(textView.selectedRange())
    }

    private func handleBackspace() -> Bool {
        let selection = textView.selectedRange()
        guard selection.length == 0 else { return false }
        let caret = selection.location
        let paragraph = paragraphRange(at: caret)
        guard caret == paragraph.location else { return false }
        let info = storage.paragraphInfo(at: paragraph)

        if info.kind == .code { return handleCodeBackspace(caret: caret) }

        if info.kind != .paragraph {
            let target = info.kind.isList && info.indent > 0
                ? ParagraphInfo(kind: info.kind, indent: info.indent - 1, checked: info.checked)
                : ParagraphInfo()
            grouped { setInfo(target, at: caret) }
            return true
        }
        guard caret > 0 else { return false }
        let previous = paragraphRange(at: caret - 1)
        let previousInfo = storage.paragraphInfo(at: previous)
        if previousInfo.kind == .rule {
            grouped { replace(previous, with: "", attributes: [:]) }
            textView.setSelectedRange(NSRange(location: previous.location, length: 0))
            return true
        }
        if previousInfo != info {
            // Joining keeps the previous block's type, like ProseMirror.
            grouped {
                replace(NSRange(location: caret - 1, length: 1), with: "", attributes: [:])
                setInfo(previousInfo, at: caret - 1)
            }
            textView.setSelectedRange(NSRange(location: caret - 1, length: 0))
            return true
        }
        return false
    }

    /// Raycast's code block Backspace at the start of a line: an empty block becomes a
    /// paragraph; any other line joins the one above (deleting the newline); the first line of
    /// a non-empty block does ProseMirror's `joinBackward`.
    private func handleCodeBackspace(caret: Int) -> Bool {
        let group = codeGroup(at: caret)
        let content = NSRange(location: group.location, length: group.length - 1)
        if content.length == 0 {
            grouped { setInfo(ParagraphInfo(), at: caret) }
            return true
        }
        guard caret == group.location else { return false }
        guard caret > 0 else { return true }
        let previous = paragraphRange(at: caret - 1)
        let previousInfo = storage.paragraphInfo(at: previous)
        switch previousInfo.kind {
        case .paragraph, .heading1, .heading2, .heading3:
            if contentRange(previous).length == 0 {
                // An empty block above is simply removed.
                grouped { replace(previous, with: "", attributes: [:]) }
                textView.setSelectedRange(NSRange(location: previous.location, length: 0))
            } else {
                // The whole block joins the text above; its newlines become spaces.
                let code = (storage.string as NSString).substring(with: content).replacingOccurrences(of: "\n", with: " ")
                var attributes = paragraphAttributes(previousInfo)
                attributes[.jotMarks] = 0
                grouped {
                    replace(NSRange(location: caret - 1, length: content.length + 1), with: code, attributes: attributes)
                    setInfo(previousInfo, at: caret - 1)
                }
                textView.setSelectedRange(NSRange(location: caret - 1, length: 0))
            }
        case .rule:
            grouped { replace(previous, with: "", attributes: [:]) }
            textView.setSelectedRange(NSRange(location: previous.location, length: 0))
        default:
            // A list item or quote above would take the block inside it, which a flat note can't hold.
            break
        }
        return true
    }

    private func handleTab(outdent: Bool) -> Bool {
        // Raycast's code block: Tab inserts a tab character; Shift-Tab removes a leading tab
        // (or one or two spaces) from the caret's line.
        if isInCodeBlock {
            let selection = textView.selectedRange()
            if !outdent {
                textView.insertText("\t", replacementRange: selection)
                return true
            }
            let line = paragraphRange(at: selection.location)
            let head = (storage.string as NSString).substring(with: NSRange(location: line.location, length: min(4, contentRange(line).length)))
            let removable = head.hasPrefix("\t") ? 1 : head.prefix(2).prefix { $0 == " " }.count
            if removable > 0 {
                grouped { replace(NSRange(location: line.location, length: removable), with: "", attributes: [:]) }
                let shifted = max(line.location, selection.location - removable)
                textView.setSelectedRange(NSRange(location: shifted, length: max(0, NSMaxRange(selection) - removable - shifted)))
            }
            return true
        }
        let paragraphs = selectedParagraphs()
        let infos = paragraphs.map { storage.paragraphInfo(at: $0) }
        if infos.allSatisfy({ $0.kind.isList }) {
            grouped {
                for (range, info) in zip(paragraphs, infos) {
                    var next = info
                    if outdent {
                        next.indent = max(0, info.indent - 1)
                    } else {
                        let previous = range.location > 0 ? storage.paragraphInfo(at: paragraphRange(at: range.location - 1)) : nil
                        let limit = previous?.kind.isList == true ? previous!.indent + 1 : 0
                        next.indent = min(info.indent + 1, limit)
                    }
                    if next != info { setInfo(next, for: [range]) }
                }
            }
            return true
        }
        return outdent
    }

    // MARK: Mouse

    func handleMouseDown(_ event: NSEvent) -> Bool {
        if handleImageMouseDown(event) { return true }
        let point = textView.convert(event.locationInWindow, from: nil)
        if let paragraph = checkboxParagraph(at: point) {
            var info = storage.paragraphInfo(at: paragraph)
            info.checked.toggle()
            grouped { setInfo(info, for: [paragraph]) }
            return true
        }
        if event.modifierFlags.contains(.command) {
            let index = textView.characterIndexForInsertion(at: point)
            for candidate in [index, index - 1] where candidate >= 0 && candidate < storage.length {
                if let href = storage.attribute(.jotHref, at: candidate, effectiveRange: nil) as? String {
                    openLink(href)
                    return true
                }
            }
        }
        return false
    }

    func isOverInteractiveMarker(_ event: NSEvent) -> Bool {
        checkboxParagraph(at: textView.convert(event.locationInWindow, from: nil)) != nil
    }

    private func checkboxParagraph(at point: NSPoint) -> NSRange? {
        let origin = textView.textContainerOrigin
        let local = CGPoint(x: point.x - origin.x, y: point.y - origin.y)
        guard let fragment = layoutManager.textLayoutFragment(for: CGPoint(x: max(0, local.x), y: local.y)) as? BlockLayoutFragment,
              let range = nsRange(fragment.rangeInElement)
        else { return nil }
        let info = storage.paragraphInfo(at: range)
        guard info.kind == .task, let line = fragment.textLineFragments.first else { return nil }
        let frame = fragment.layoutFragmentFrame
        let rect = fragment.checkboxRect(
            textX: frame.minX + line.typographicBounds.minX,
            baseline: frame.minY + line.typographicBounds.minY + line.glyphOrigin.y
        ).insetBy(dx: -4, dy: -4)
        return rect.contains(local) ? range : nil
    }

    func nsRange(_ textRange: NSTextRange) -> NSRange? {
        let start = contentStorage.offset(from: contentStorage.documentRange.location, to: textRange.location)
        let length = contentStorage.offset(from: textRange.location, to: textRange.endLocation)
        guard start != NSNotFound, length != NSNotFound else { return nil }
        return NSRange(location: start, length: length)
    }

    func textRange(_ range: NSRange) -> NSTextRange? {
        guard let start = contentStorage.location(contentStorage.documentRange.location, offsetBy: range.location),
              let end = contentStorage.location(start, offsetBy: range.length)
        else { return nil }
        return NSTextRange(location: start, end: end)
    }

    private func openLink(_ href: String) {
        let candidate = href.contains("://") || href.hasPrefix("mailto:") ? href : "https://" + href
        if let url = URL(string: candidate) { NSWorkspace.shared.open(url) }
    }

    // MARK: Commands (menu + format bar)

    func toggleMark(_ mark: Marks) {
        let selection = textView.selectedRange()
        // Code blocks take no marks (`marks: ''`), so Raycast's toggles do nothing there.
        if selection.length == 0, isInCodeBlock { return }
        if selection.length == 0 {
            var marks = Marks(rawValue: textView.typingAttributes[.jotMarks] as? Int ?? 0)
            if marks.contains(mark) { marks.remove(mark) } else { marks.insert(mark) }
            let info = self.info(at: selection.location)
            textView.typingAttributes = restyler.typingAttributes(
                info: info, marks: marks, href: nil,
                paragraphStyle: textView.typingAttributes[.paragraphStyle] as? NSParagraphStyle
            )
            onSelectionChange?()
            return
        }
        var allHave = true
        storage.enumerateAttribute(.jotMarks, in: selection) { value, range, stop in
            if (storage.string as NSString).substring(with: range) == "\n" { return }
            if !Marks(rawValue: value as? Int ?? 0).contains(mark) { allHave = false; stop.pointee = true }
        }
        guard textView.shouldChangeText(in: selection, replacementString: nil) else { return }
        storage.beginEditing()
        storage.enumerateAttribute(.jotMarks, in: selection) { value, range, _ in
            var marks = Marks(rawValue: value as? Int ?? 0)
            if allHave { marks.remove(mark) } else { marks.insert(mark) }
            storage.addAttribute(.jotMarks, value: marks.rawValue, range: range)
        }
        storage.endEditing()
        textView.didChangeText()
        onSelectionChange?()
    }

    func toggleBlock(_ kind: BlockKind) {
        // Images aren't text, so block formatting passes over them.
        let paragraphs = selectedParagraphs().filter { storage.paragraphInfo(at: $0).kind != .image }
        let infos = paragraphs.map { storage.paragraphInfo(at: $0) }
        let allSame = infos.allSatisfy { $0.kind == kind }
        grouped {
            for (range, info) in zip(paragraphs, infos) {
                let target = allSame
                    ? ParagraphInfo()
                    : ParagraphInfo(kind: kind, indent: kind.isList && info.kind.isList ? info.indent : 0, checked: kind == .task && info.checked)
                setInfo(target, for: [range])
            }
        }
        onSelectionChange?()
    }

    /// ⌘↩: toggles a task's checkbox, exits a code block, or turns text into a task.
    func toggleTask() {
        let paragraphs = selectedParagraphs()
        let infos = paragraphs.map { storage.paragraphInfo(at: $0) }
        if infos.first?.kind == .code {
            exitCodeBlock()
            return
        }
        grouped {
            for (range, info) in zip(paragraphs, infos) {
                let target = info.kind == .task
                    ? ParagraphInfo(kind: .task, indent: info.indent, checked: !info.checked)
                    : ParagraphInfo(kind: .task, indent: info.kind.isList ? info.indent : 0)
                setInfo(target, for: [range])
            }
        }
    }

    /// Whether the caret is in a list item ("Move List Item Up/Down").
    var isInListItem: Bool { info(at: textView.selectedRange().location).kind.isList }

    /// Swaps the current list item with its neighbour, keeping the caret in it.
    func moveListItem(up: Bool) {
        let caret = textView.selectedRange().location
        let current = paragraphRange(at: caret)
        guard storage.paragraphInfo(at: current).kind.isList else { return }
        let neighbour: NSRange
        if up {
            guard current.location > 0 else { return }
            neighbour = paragraphRange(at: current.location - 1)
        } else {
            guard NSMaxRange(current) < storage.length - 1 else { return }
            neighbour = paragraphRange(at: NSMaxRange(current))
        }
        guard storage.paragraphInfo(at: neighbour).kind.isList else { return }
        let first = up ? neighbour : current
        let second = up ? current : neighbour
        let swapped = NSMutableAttributedString(attributedString: storage.attributedSubstring(from: second))
        swapped.append(storage.attributedSubstring(from: first))
        let offsetInCurrent = caret - current.location
        grouped { replace(NSUnionRange(first, second), with: swapped) }
        let newStart = up ? first.location : first.location + second.length
        textView.setSelectedRange(NSRange(location: newStart + offsetInCurrent, length: 0))
        textView.scrollRangeToVisible(textView.selectedRange())
    }

    func insertRule() {
        let caret = textView.selectedRange().location
        let paragraph = paragraphRange(at: caret)
        let ruleAttributes = paragraphAttributes(ParagraphInfo(kind: .rule))
        grouped {
            replace(NSRange(location: NSMaxRange(paragraph), length: 0), with: "\n", attributes: ruleAttributes)
            replace(NSRange(location: NSMaxRange(paragraph) + 1, length: 0), with: "\n", attributes: paragraphAttributes(ParagraphInfo()))
        }
        textView.setSelectedRange(NSRange(location: NSMaxRange(paragraph) + 1, length: 0))
    }

    /// The link under the caret (or across the selection) and its range.
    func currentLink() -> (href: String?, range: NSRange) {
        let selection = textView.selectedRange()
        let index = selection.length > 0 ? selection.location : max(0, selection.location - 1)
        if index < storage.length {
            var range = NSRange()
            if let href = storage.attribute(.jotHref, at: index, longestEffectiveRange: &range, in: paragraphRange(at: index)) as? String {
                return (href, selection.length > 0 ? selection : range)
            }
        }
        return (nil, selection)
    }

    func setLink(_ href: String?, range: NSRange) {
        let trimmed = href?.trimmingCharacters(in: .whitespacesAndNewlines)
        let value = trimmed?.isEmpty == false ? trimmed : nil
        if range.length == 0 {
            guard let value else { return }
            var attributes = textView.typingAttributes
            attributes[.jotHref] = value
            grouped { replace(range, with: value, attributes: attributes) }
            textView.setSelectedRange(NSRange(location: range.location + value.utf16.count, length: 0))
            return
        }
        guard textView.shouldChangeText(in: range, replacementString: nil) else { return }
        if let value { storage.addAttribute(.jotHref, value: value, range: range) }
        else { storage.removeAttribute(.jotHref, range: range) }
        textView.didChangeText()
    }

    // MARK: Pasteboard

    /// Whether the selection is the whole note (ProseMirror's `AllSelection`, a closed slice).
    private var selectsWholeNote: Bool {
        let selection = textView.selectedRange()
        return selection.location == 0 && NSMaxRange(selection) >= storage.length
    }

    /// The selection for `com.sourabh.jot.blocks`. Raycast copies a selection inside one code
    /// block as bare `<code>…</code>` HTML, which pastes into other blocks as inline code with
    /// collapsed whitespace; the blocks are shaped the same way here.
    func selectionJSON() -> String {
        var blocks = DocumentCodec.blocks(storage, in: textView.selectedRange())
        if !selectsWholeNote, let node = PlainText.nodes(blocks).first, PlainText.nodes(blocks).count == 1,
           case .code(_, let code) = node {
            let inline = code.replacing(/[ \t\r\n\u{000C}]+/, with: " ")
            blocks = [Block(kind: .paragraph, runs: inline.isEmpty ? [] : [Run(text: inline, marks: .code)])]
        }
        return TiptapCodec.encodeString(blocks)
    }

    /// The selection as `text/plain`, the way Raycast's copy handler writes it.
    func selectionPlainText() -> String {
        PlainText.clipboard(DocumentCodec.blocks(storage, in: textView.selectedRange()), partial: !selectsWholeNote)
    }

    /// Pastes blocks the way ProseMirror inserts an open slice: into an empty block they land
    /// as they are; a single block's content goes inline and the block keeps its type;
    /// otherwise the first pasted block joins the text before the caret (keeping this block's
    /// type) and the last one takes the text after it. Code blocks and headings stay whole
    /// (`defining`), so they split the block instead of merging into it.
    func paste(_ blocks: [Block]) {
        guard !blocks.isEmpty else { return }
        grouped {
            var selection = textView.selectedRange()
            if selection.length > 0 {
                let first = info(at: selection.location)
                let spansBlocks = paragraphRange(at: selection.location) != paragraphRange(at: NSMaxRange(selection) - 1)
                replace(selection, with: "", attributes: [:])
                if spansBlocks { setInfo(first, at: selection.location) }
                selection.length = 0
            }
            let paragraph = paragraphRange(at: selection.location)
            guard let current = DocumentCodec.blocks(storage, in: paragraph).first else { return }
            let (before, after) = Self.split(current.runs, at: selection.location - paragraph.location)
            let isDefining: (Block) -> Bool = { $0.kind == .code || $0.kind.isHeading || $0.kind == .image }
            let afterLength = after.reduce(0) { $0 + $1.text.utf16.count }

            var result: [Block]
            var caretBlock: Int
            var caretOffset: Int
            if current.runs.isEmpty {
                result = blocks
                caretBlock = result.count - 1
                caretOffset = result[caretBlock].text.utf16.count
            } else if blocks.count == 1, !isDefining(blocks[0]) {
                var merged = current
                merged.runs = before + blocks[0].runs + after
                result = [merged]
                caretBlock = 0
                caretOffset = merged.text.utf16.count - afterLength
            } else {
                result = blocks
                if isDefining(blocks[0]) {
                    if !before.isEmpty {
                        var head = current
                        head.runs = before
                        result.insert(head, at: 0)
                    }
                } else {
                    var head = current
                    head.runs = before + blocks[0].runs
                    result[0] = head
                }
                if after.isEmpty {
                    caretBlock = result.count - 1
                    caretOffset = result[caretBlock].text.utf16.count
                } else if isDefining(result[result.count - 1]) {
                    caretBlock = result.count - 1
                    caretOffset = result[caretBlock].text.utf16.count
                    var tail = current
                    tail.runs = after
                    result.append(tail)
                } else {
                    result[result.count - 1].runs += after
                    caretBlock = result.count - 1
                    caretOffset = result[caretBlock].text.utf16.count - afterLength
                }
            }
            replace(paragraph, with: DocumentCodec.attributedString(result))
            let caret = paragraph.location + result[..<caretBlock].reduce(0) { $0 + $1.text.utf16.count + 1 } + caretOffset
            textView.setSelectedRange(NSRange(location: caret, length: 0))
        }
        updateTypingAttributes()
        textView.scrollRangeToVisible(textView.selectedRange())
    }

    /// Splits runs at a UTF-16 offset.
    private static func split(_ runs: [Run], at offset: Int) -> ([Run], [Run]) {
        var before: [Run] = []
        var after: [Run] = []
        var position = 0
        for run in runs {
            let length = run.text.utf16.count
            if position + length <= offset {
                before.append(run)
            } else if position >= offset {
                after.append(run)
            } else {
                let units = Array(run.text.utf16)
                let cut = offset - position
                var head = run
                var tail = run
                head.text = String(decoding: units[..<cut], as: UTF16.self)
                tail.text = String(decoding: units[cut...], as: UTF16.self)
                before.append(head)
                after.append(tail)
            }
            position += length
        }
        return (before, after)
    }

    /// Plain text into a code block goes in as it is, newlines included.
    func paste(plainText: String) {
        let selection = textView.selectedRange()
        var attributes = textView.typingAttributes
        attributes[.jotHref] = nil
        let text = plainText.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        grouped { replace(selection, with: text, attributes: attributes) }
        textView.setSelectedRange(NSRange(location: selection.location + text.utf16.count, length: 0))
        textView.scrollRangeToVisible(textView.selectedRange())
    }

    // MARK: Find highlights

    func setFindHighlights(_ ranges: [NSRange], active: Int?) {
        layoutManager.removeRenderingAttribute(.backgroundColor, for: contentStorage.documentRange)
        layoutManager.removeRenderingAttribute(.foregroundColor, for: contentStorage.documentRange)
        for (i, range) in ranges.enumerated() {
            guard let textRange = textRange(range) else { continue }
            if i == active {
                layoutManager.addRenderingAttribute(.backgroundColor, value: Theme.yellow, for: textRange)
                layoutManager.addRenderingAttribute(.foregroundColor, value: NSColor.black, for: textRange)
            } else {
                layoutManager.addRenderingAttribute(.backgroundColor, value: Theme.yellow40, for: textRange)
            }
        }
        if let active, active < ranges.count {
            textView.scrollRangeToVisible(ranges[active])
        }
    }

    func replaceText(in ranges: [NSRange], with replacement: String) {
        grouped {
            for range in ranges.sorted(by: { $0.location > $1.location }) {
                let attributes = storage.attributes(at: range.location, effectiveRange: nil)
                replace(range, with: replacement, attributes: attributes)
            }
        }
    }

    var text: String { storage.string }

    // MARK: Zoom & appearance

    private func applyZoom() {
        restyler.restyle(storage)
        updateFirstBlockSpacing()
        layoutManager.invalidateLayout(for: contentStorage.documentRange)
        updateTypingAttributes()
        updatePlaceholder()
        onLayout?()
    }

    func appearanceDidChange() {
        layoutManager.invalidateLayout(for: contentStorage.documentRange)
        textView.needsDisplay = true
    }
}

// MARK: - Delegates

extension NoteEditor: NSTextViewDelegate {
    func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        if let handled = slashMenu.handle(selector) { return handled }
        if let handled = handleImageCommand(selector) { return handled }
        switch selector {
        case #selector(NSResponder.insertNewline(_:)):
            if NSApp.currentEvent?.modifierFlags.contains(.shift) == true { return insertHardBreak() }
            return handleEnter()
        case #selector(NSResponder.insertLineBreak(_:)), #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)):
            return insertHardBreak()
        case #selector(NSResponder.deleteBackward(_:)):
            return handleBackspace()
        case #selector(NSResponder.insertTab(_:)):
            return handleTab(outdent: false)
        case #selector(NSResponder.insertBacktab(_:)):
            return handleTab(outdent: true)
        default:
            return false
        }
    }

    /// Tiptap's `setHardBreak`: `exitCode` first, so Shift-Enter leaves a code block.
    private func insertHardBreak() -> Bool {
        if isInCodeBlock {
            exitCodeBlock()
        } else {
            textView.insertText("\u{2028}", replacementRange: textView.selectedRange())
        }
        return true
    }

    func textDidChange(_ notification: Notification) {
        guard !isLoading else { return }
        // Invariant: the text always ends with a newline that anchors the last block.
        if storage.length == 0 || (storage.string as NSString).character(at: storage.length - 1) != 0x0A {
            let attributes = storage.length > 0 ? storage.attributes(at: storage.length - 1, effectiveRange: nil) : paragraphAttributes(ParagraphInfo())
            let selection = textView.selectedRange()
            storage.append(NSAttributedString(string: "\n", attributes: attributes.filter { $0.key != .jotMarks && $0.key != .jotHref }))
            textView.setSelectedRange(selection)
        }
        if commandDepth == 0 { normalizeImageBlocks() }
        ensureTrailingParagraph()
        updatePlaceholder()
        slashMenu.update()
        onChange?()
        onLayout?()
    }

    func textViewDidChangeSelection(_ notification: Notification) {
        guard !isLoading else { return }
        normalizeSelection()
        updateImageSelection()
        updateTypingAttributes()
        slashMenu.update()
        onSelectionChange?()
    }
}

extension NoteEditor: @preconcurrency NSTextStorageDelegate {
    func textStorage(_ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions, range editedRange: NSRange, changeInLength delta: Int) {
        guard !isLoading, editedMask.contains(.editedCharacters) || editedMask.contains(.editedAttributes) else { return }
        if editedMask.contains(.editedCharacters) { slashMenu.map(edited: editedRange, changeInLength: delta) }
        restyler.restyle(textStorage)
        updateFirstBlockSpacing()
    }
}

extension NoteEditor: @preconcurrency NSTextLayoutManagerDelegate {
    func textLayoutManager(_ textLayoutManager: NSTextLayoutManager, textLayoutFragmentFor location: any NSTextLocation, in textElement: NSTextElement) -> NSTextLayoutFragment {
        let fragment = BlockLayoutFragment(textElement: textElement, range: textElement.elementRange)
        fragment.style = style
        fragment.appearance = textView.effectiveAppearance
        fragment.attachments = attachments
        return fragment
    }
}

/// Markdown-style inline shortcuts: `**bold**`, `*italic*`, `` `code` ``, `~~strike~~`.
private enum InlineRule {
    struct Match {
        var spanOffset: Int
        var delimiterLength: Int
        var innerLength: Int
        var mark: Marks
    }

    private static let rules: [(String, Marks)] = [("**", .bold), ("__", .bold), ("~~", .strike), ("`", .code), ("*", .italic), ("_", .italic)]

    static func match(_ text: String) -> Match? {
        let units = Array(text.utf16)
        for (delimiter, mark) in rules {
            let d = Array(delimiter.utf16)
            guard units.count > d.count * 2, Array(units.suffix(d.count)) == d else { continue }
            let closeStart = units.count - d.count
            if d.count == 1, closeStart > 0, units[closeStart - 1] == d[0] { continue } // part of `**`
            var search = closeStart - 1
            while search - d.count + 1 >= 0 {
                let openStart = search - d.count + 1
                if Array(units[openStart...search]) == d {
                    let innerStart = openStart + d.count
                    let innerLength = closeStart - innerStart
                    guard innerLength > 0 else { break }
                    let inner = Array(units[innerStart..<closeStart])
                    if d.count == 1 {
                        if openStart > 0, units[openStart - 1] == d[0] { break }
                        if inner.first == d[0] { break }
                    }
                    if mark != .code, inner.first == 0x20 || inner.last == 0x20 { break }
                    if delimiter == "_", openStart > 0, isWordCharacter(units[openStart - 1]) { break }
                    return Match(spanOffset: openStart, delimiterLength: d.count, innerLength: innerLength, mark: mark)
                }
                if mark == .code, units[search] == 0x60 { break }
                search -= 1
            }
        }
        return nil
    }

    private static func isWordCharacter(_ unit: UInt16) -> Bool {
        guard let scalar = Unicode.Scalar(unit) else { return false }
        return CharacterSet.alphanumerics.contains(scalar)
    }
}
