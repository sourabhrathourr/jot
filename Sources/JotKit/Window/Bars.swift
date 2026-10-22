import AppKit

/// The 52pt header, laid out like Raycast's `.topbarMacInner` grid:
/// `[spacer (= actions width)] 16 [title, centred, truncating] 16 [actions]`, padding 0 8.
/// The spacer mirrors the actions so the title is centred on the window and never
/// reaches the traffic lights. Title style is the `text` variant in `secondary`.
/// Both fade when the pointer leaves the window (title → 30%, actions → hidden).
final class TopBar: DragView {
    let titleLabel = Chrome.label("Untitled", size: 13, color: Theme.textSecondary)
    private let spacer = NSView()
    private let actions: GlassPill
    /// Raycast: `<ProgressiveBlur height={52} position="top" style={{ zIndex: -1 }} />`.
    private let blur = ProgressiveBlurView()

    init(target: AnyObject, browse: Selector, more: Selector, new: Selector) {
        // Raycast: `NativeButtonGroup` of `NativeIconButton`s, variant `tertiary`, size `small`
        // (28pt), icons `command-symbol-20`, `docs-stacked-20`, `plus-20`.
        func icon(_ name: String, _ action: Selector, _ tip: String) -> ChromeIconButton {
            ChromeIconButton(icon: name, size: 28, iconSize: 20, tooltip: tip) { [weak target] in
                NSApp.sendAction(action, to: target, from: nil)
            }
        }
        let stack = NSStackView(views: [
            icon("command-symbol-20", more, "Action Panel  ⌘K"),
            icon("docs-stacked-20", browse, "Browse Notes  ⌘P"),
            icon("plus-20", new, "Create Note  ⌘N"),
        ])
        stack.spacing = 0
        // The group is exactly its buttons (4 + 3 × 28 + 4); without this the spacer/actions
        // pair stretched to absorb free space instead of the title.
        stack.setHuggingPriority(.required, for: .horizontal)
        actions = GlassPill(content: stack, cornerRadius: 18)
        actions.widthAnchor.constraint(equalToConstant: 4 + 28 * 3 + 4).isActive = true
        actions.heightAnchor.constraint(equalToConstant: 4 + 28 + 4).isActive = true
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        titleLabel.alignment = .center
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1
        titleLabel.cell?.truncatesLastVisibleLine = true
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        titleLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        spacer.translatesAutoresizingMaskIntoConstraints = false

        addSubview(blur)
        addSubview(spacer)
        addSubview(titleLabel)
        addSubview(actions)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: Layout.headerHeight),
            blur.topAnchor.constraint(equalTo: topAnchor),
            blur.bottomAnchor.constraint(equalTo: bottomAnchor),
            blur.leadingAnchor.constraint(equalTo: leadingAnchor),
            blur.trailingAnchor.constraint(equalTo: trailingAnchor),
            spacer.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            spacer.widthAnchor.constraint(equalTo: actions.widthAnchor),
            spacer.heightAnchor.constraint(equalToConstant: 1),
            spacer.centerYAnchor.constraint(equalTo: centerYAnchor),
            actions.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            actions.centerYAnchor.constraint(equalTo: centerYAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: spacer.trailingAnchor, constant: 16),
            titleLabel.trailingAnchor.constraint(equalTo: actions.leadingAnchor, constant: -16),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    /// `.text__size-13` is 13px, minus 0.1px on 1x displays (`@media (resolution: 1x)`).
    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        let size: CGFloat = (window?.backingScaleFactor ?? 2) < 2 ? 12.9 : 13
        titleLabel.font = Fonts.ui(size: size)
    }

    func setHovered(_ hovered: Bool) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Layout.chromeFade
            titleLabel.animator().alphaValue = hovered ? 1 : 0.3
            actions.animator().alphaValue = hovered ? 1 : 0
        }
    }
}

/// The footer: a character counter, or the glass format pill, plus a glass toggle.
final class BottomBar: NSView {
    let counter = NSButton(title: "", target: nil, action: nil)
    let headingButton: FormatButton
    let boldButton: FormatButton
    let italicButton: FormatButton
    let strikeButton: FormatButton
    let underlineButton: FormatButton
    let codeButton: FormatButton
    let linkButton: FormatButton
    let listButton: FormatButton
    let quoteButton: FormatButton
    let codeBlockButton: FormatButton
    private let pill: GlassPill
    private let toggle: ChromeIconButton
    private let toggleGlass: GlassPill
    private(set) var isFormatBarVisible = false
    private var isHovered = true

    init(target: AnyObject) {
        func button(_ symbol: String, _ action: String, _ tip: String) -> FormatButton {
            Chrome.plainButton(symbol, target: target, action: Selector(action), tooltip: tip)
        }
        headingButton = button("heading", "showHeadingMenu:", "Heading")
        boldButton = button("bold", "toggleBold:", "Bold (⌘B)")
        italicButton = button("italics", "toggleItalic:", "Italic (⌘I)")
        strikeButton = button("strike-through", "toggleStrike:", "Strikethrough (⇧⌘S)")
        underlineButton = button("underline", "toggleUnderline:", "Underline (⌘U)")
        codeButton = button("code", "toggleInlineCode:", "Code (⌘E)")
        linkButton = button("link", "editLink:", "Link (⌘L)")
        listButton = button("bullet-points", "showListMenu:", "List")
        quoteButton = button("quote-block", "toggleQuote:", "Quote (⇧⌘B)")
        codeBlockButton = button("code-block", "toggleCodeBlock:", "Code Block (⌥⌘C)")

        let stack = NSStackView(views: [
            headingButton, Chrome.divider(height: 16),
            boldButton, italicButton, strikeButton, underlineButton, Chrome.divider(height: 16),
            codeButton, linkButton, Chrome.divider(height: 16),
            listButton, quoteButton, codeBlockButton,
        ])
        stack.orientation = .horizontal
        stack.spacing = 4
        pill = GlassPill(content: stack, cornerRadius: 18)
        // Raycast: `NativeIconButton` variant `glass`, 32pt, icon `text` / `x-mark-circle-filled`.
        toggle = ChromeIconButton(icon: "text", size: 32, iconSize: 16, tooltip: "Show Format Buttons  ⌥⌘,") { [weak target] in
            NSApp.sendAction(Selector(("toggleFormatBar:")), to: target, from: nil)
        }
        toggleGlass = GlassPill(content: toggle, cornerRadius: 16, padding: 0)
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        counter.isBordered = false
        counter.font = Fonts.ui(size: 12, tabularNumbers: true)
        counter.contentTintColor = Theme.textTertiary
        counter.target = target
        counter.action = Selector(("toggleCounterMode:"))
        counter.translatesAutoresizingMaskIntoConstraints = false

        pill.alphaValue = 0
        pill.isHidden = true
        addSubview(counter)
        addSubview(pill)
        addSubview(toggleGlass)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 36),
            counter.centerXAnchor.constraint(equalTo: centerXAnchor),
            counter.centerYAnchor.constraint(equalTo: centerYAnchor),
            pill.centerXAnchor.constraint(equalTo: centerXAnchor),
            pill.centerYAnchor.constraint(equalTo: centerYAnchor),
            pill.trailingAnchor.constraint(lessThanOrEqualTo: toggleGlass.leadingAnchor, constant: -8),
            toggleGlass.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            toggleGlass.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func setCounterText(_ text: String) {
        counter.attributedTitle = NSAttributedString(string: text, attributes: [
            .font: Fonts.ui(size: 12, tabularNumbers: true),
            .foregroundColor: Theme.textTertiary,
        ])
    }

    func setFormatBarVisible(_ visible: Bool, animated: Bool = true) {
        isFormatBarVisible = visible
        toggle.icon = visible ? "x-mark-circle-filled" : "text"
        toggle.toolTip = visible ? "Hide Format Buttons  ⌥⌘," : "Show Format Buttons  ⌥⌘,"
        pill.isHidden = false
        counter.isHidden = false
        NSAnimationContext.runAnimationGroup { context in
            context.duration = animated ? Layout.chromeFade : 0
            pill.animator().alphaValue = visible ? (isHovered ? 1 : 0.3) : 0
            counter.animator().alphaValue = visible ? 0 : 1
        } completionHandler: { [weak self] in
            guard let self else { return }
            pill.isHidden = !isFormatBarVisible
            counter.isHidden = isFormatBarVisible
        }
    }

    func setHovered(_ hovered: Bool) {
        isHovered = hovered
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Layout.chromeFade
            toggleGlass.animator().alphaValue = hovered ? 1 : 0
            if isFormatBarVisible { pill.animator().alphaValue = hovered ? 1 : 0.3 }
        }
    }

    func update(_ state: EditorState) {
        headingButton.isActive = state.block.isHeading
        boldButton.isActive = state.marks.contains(.bold)
        italicButton.isActive = state.marks.contains(.italic)
        strikeButton.isActive = state.marks.contains(.strike)
        underlineButton.isActive = state.marks.contains(.underline)
        codeButton.isActive = state.marks.contains(.code)
        linkButton.isActive = state.hasLink
        listButton.isActive = state.block.isList
        quoteButton.isActive = state.block == .quote
        codeBlockButton.isActive = state.block == .code
    }
}

/// ⌘F: a glass find & replace bar pinned under the header.
final class FindBar: NSGlassEffectView, NSTextFieldDelegate {
    var onQueryChange: ((String) -> Void)?
    var onNext: (() -> Void)?
    var onPrevious: (() -> Void)?
    var onClose: (() -> Void)?
    var onReplace: ((String) -> Void)?
    var onReplaceAll: ((String) -> Void)?

    let findField = NSTextField()
    let replaceField = NSTextField()
    private let countLabel = Chrome.label("", size: 12, color: Theme.textSecondary)
    private let replaceRow = NSStackView()
    private let chevron = NSButton()

    init() {
        super.init(frame: .zero)
        cornerRadius = 18
        translatesAutoresizingMaskIntoConstraints = false

        for (field, placeholder) in [(findField, "Find"), (replaceField, "Replace")] {
            field.placeholderString = placeholder
            field.isBordered = false
            field.drawsBackground = false
            field.focusRingType = .none
            field.font = Fonts.ui(size: 13)
            field.delegate = self
            field.translatesAutoresizingMaskIntoConstraints = false
        }

        chevron.image = Chrome.symbol("chevron.right", size: 11)
        chevron.isBordered = false
        chevron.contentTintColor = Theme.textSecondary
        chevron.target = self
        chevron.action = #selector(toggleReplace)

        func icon(_ name: String, _ action: Selector, _ tip: String) -> NSButton {
            let button = NSButton(image: Chrome.symbol(name, size: 12) ?? NSImage(), target: self, action: action)
            button.isBordered = false
            button.contentTintColor = Theme.textSecondary
            button.toolTip = tip
            return button
        }

        let findRow = NSStackView(views: [
            chevron, findField, countLabel, Chrome.divider(height: 14),
            icon("chevron.up", #selector(previous), "Previous Match (⇧↩)"),
            icon("chevron.down", #selector(next), "Next Match (↩)"),
            icon("xmark", #selector(close), "Close (Esc)"),
        ])
        findRow.spacing = 8
        findRow.edgeInsets = NSEdgeInsets(top: 4, left: 4, bottom: 4, right: 4)

        let replaceOne = NSButton(title: "Replace", target: self, action: #selector(replaceCurrent))
        let replaceAll = NSButton(title: "All", target: self, action: #selector(replaceEverything))
        for button in [replaceOne, replaceAll] {
            button.bezelStyle = .glass
            button.controlSize = .small
            button.font = Fonts.ui(size: 12)
        }
        replaceRow.setViews([replaceField, replaceOne, replaceAll], in: .leading)
        replaceRow.spacing = 8
        replaceRow.edgeInsets = NSEdgeInsets(top: 4, left: 30, bottom: 4, right: 4)
        replaceRow.isHidden = true

        let column = NSStackView(views: [findRow, replaceRow])
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = 4
        column.edgeInsets = NSEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        findRow.widthAnchor.constraint(equalTo: column.widthAnchor, constant: -16).isActive = true
        replaceRow.widthAnchor.constraint(equalTo: column.widthAnchor, constant: -16).isActive = true
        contentView = column
    }

    required init?(coder: NSCoder) { fatalError() }

    func setCount(current: Int?, total: Int) {
        countLabel.stringValue = total == 0
            ? (findField.stringValue.isEmpty ? "" : "No results")
            : "\((current ?? 0) + 1)/\(total)"
    }

    @objc private func toggleReplace() {
        replaceRow.isHidden.toggle()
        chevron.image = Chrome.symbol(replaceRow.isHidden ? "chevron.right" : "chevron.down", size: 11)
    }

    @objc private func next() { onNext?() }
    @objc private func previous() { onPrevious?() }
    @objc private func close() { onClose?() }
    @objc private func replaceCurrent() { onReplace?(replaceField.stringValue) }
    @objc private func replaceEverything() { onReplaceAll?(replaceField.stringValue) }

    func controlTextDidChange(_ notification: Notification) {
        if (notification.object as? NSTextField) === findField { onQueryChange?(findField.stringValue) }
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.insertNewline(_:)):
            if control === replaceField { onReplace?(replaceField.stringValue) }
            else if NSApp.currentEvent?.modifierFlags.contains(.shift) == true { onPrevious?() }
            else { onNext?() }
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            onClose?()
            return true
        default:
            return false
        }
    }
}
