import AppKit
import UniformTypeIdentifiers

/// The notes window: Raycast's window material + editor + chrome, persistence, auto-height,
/// find & replace, zoom, and every command in the menus.
final class NotesWindowController: NSWindowController, NSWindowDelegate, NSMenuItemValidation {
    let panel = NotesPanel()
    let editor = NoteEditor()
    private let repository: NotesRepository
    private let root = HoverView()
    private let edgeFade = CAGradientLayer()
    private lazy var topBar = TopBar(target: self, browse: #selector(browseNotes(_:)), more: #selector(showActionsMenu(_:)), new: #selector(newNote(_:)))
    private lazy var bottomBar = BottomBar(target: self)
    private let findBar = FindBar()
    private var menuPanel: CommandMenuPanel?
    private var backStack: [String] = []
    private var forwardStack: [String] = []
    private let linkPopover = LinkPopover()

    private(set) var current: Note?
    private var saveTask: Task<Void, Never>?
    private var isDirty = false
    private var isHovered = true
    private var isResizingProgrammatically = false
    private var findMatches: [NSRange] = []
    private var findIndex: Int?
    private let toasts = ToastHost()

    /// The scroll viewport's padding (the 52pt header) plus the editor's own 4px padding,
    /// putting the first line box 64pt down, as in Raycast.
    private static let chromeInset: CGFloat = Layout.headerHeight + Layout.editorVerticalPadding

    private let defaults = UserDefaults.standard
    private var isAutoSizing: Bool {
        get { defaults.object(forKey: "autoSize") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "autoSize") }
    }
    private var showsWords: Bool {
        get { defaults.bool(forKey: "counterShowsWords") }
        set { defaults.set(newValue, forKey: "counterShowsWords") }
    }
    private var zoom: CGFloat {
        get { CGFloat(defaults.object(forKey: "zoom") as? Double ?? 1) }
        set { defaults.set(Double(newValue), forKey: "zoom") }
    }

    init(repository: NotesRepository) {
        self.repository = repository
        super.init(window: panel)
        panel.delegate = self
        buildLayout()
        wireEditor()
        editor.style.zoom = zoom
        bottomBar.setFormatBarVisible(defaults.bool(forKey: "formatBarVisible"), animated: false)

        if !applyDebugFrame() {
            panel.setFrameAutosaveName("JotNotesPanel")
            if !panel.setFrameUsingName("JotNotesPanel") { panel.center() }
        }
        panel.onHeaderDoubleClick = { [weak self] in self?.headerDoubleClicked() }
        openInitialNote()
    }

    required init?(coder: NSCoder) { fatalError() }

    /// `JOT_FRAME=x,y,w,h` (top-left screen coordinates) pins the window for screenshot
    /// comparisons. Nothing about it is persisted (no autosave, auto-size untouched).
    private var isFramePinned = false
    private var didOpenDebugMenu = false

    private func applyDebugFrame() -> Bool {
        guard let spec = ProcessInfo.processInfo.environment["JOT_FRAME"],
              let screen = NSScreen.screens.first else { return false }
        let v = spec.split(separator: ",").compactMap { Double($0) }
        guard v.count == 4 else { return false }
        isFramePinned = true
        panel.setFrame(NSRect(x: v[0], y: screen.frame.height - v[1] - v[3], width: v[2], height: v[3]), display: true)
        return true
    }

    /// Raycast (`register-query-client`, notes window): double-clicking the drag region
    /// re-enables auto-size if it was turned off by a manual resize, otherwise zooms.
    private func headerDoubleClicked() {
        if !isAutoSizing {
            isAutoSizing = true
            autoSize(animated: true)
        } else {
            panel.zoom(nil)
        }
    }

    // MARK: Layout

    private func buildLayout() {
        let backdrop = WindowBackdropView(cornerRadius: Layout.windowCornerRadius)
        backdrop.contentView = root
        panel.contentView = backdrop

        WindowCornerRadius.install(on: panel)
        GlassRecipe.apply(to: panel)

        let scrollView = editor.scrollView
        editor.verticalInset = Self.chromeInset
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        findBar.isHidden = true

        for view in [scrollView, topBar, findBar, bottomBar, toasts] { root.addSubview(view) }
        scrollView.wantsLayer = true
        scrollView.layer?.mask = edgeFade
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: root.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            topBar.topAnchor.constraint(equalTo: root.topAnchor),
            topBar.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            topBar.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            findBar.topAnchor.constraint(equalTo: root.topAnchor, constant: 54),
            findBar.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
            findBar.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16),
            bottomBar.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -4),
            bottomBar.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            bottomBar.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            toasts.topAnchor.constraint(equalTo: root.topAnchor),
            toasts.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            toasts.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            toasts.trailingAnchor.constraint(equalTo: root.trailingAnchor),
        ])

        root.onHoverChange = { [weak self] hovered in self?.setHovered(hovered) }
        if let title = ProcessInfo.processInfo.environment["JOT_TOAST"] {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.showToast(title) }
        }

        scrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(scrolled), name: NSView.boundsDidChangeNotification, object: scrollView.contentView)

        findBar.onQueryChange = { [weak self] _ in self?.runFind(keepIndex: false) }
        findBar.onNext = { [weak self] in self?.stepFind(1) }
        findBar.onPrevious = { [weak self] in self?.stepFind(-1) }
        findBar.onClose = { [weak self] in self?.hideFind() }
        findBar.onReplace = { [weak self] in self?.replaceCurrent(with: $0) }
        findBar.onReplaceAll = { [weak self] in self?.replaceAll(with: $0) }
    }

    @objc private func scrolled() { updateEdgeFade() }

    func windowDidResize(_ notification: Notification) { updateEdgeFade() }

    /// Raycast's scroll-area `topEdge: chrome` / `bottomEdge: chrome` mask: content fades
    /// as it scrolls under the header (84pt = header + 32, down to 15% at the midpoint)
    /// and the footer (76pt = footer + 28, down to 25%), ramping in over that much scroll.
    private func updateEdgeFade() {
        let scrollView = editor.scrollView
        let height = scrollView.bounds.height
        guard height > 0 else { return }
        let offset = scrollView.contentView.bounds.origin.y
        let documentHeight = scrollView.documentView?.frame.height ?? 0
        let canScroll = documentHeight > height + 1

        let topHeight = Layout.headerHeight + 32
        let bottomHeight = Layout.footerHeight + 28
        let topProgress = canScroll ? min(1, max(0, offset / topHeight)) : 0
        let bottomProgress = canScroll ? min(1, max(0, (documentHeight - offset - height) / bottomHeight)) : 0
        let topOpacity = 1 - (1 - 0.15) * topProgress
        let bottomOpacity = 1 - (1 - 0.25) * bottomProgress

        // Stops measured from the top of the viewport.
        let stops: [(CGFloat, CGFloat)] = [
            (0, canScroll ? 0 : 1),
            (topHeight * 0.5 * topProgress, topOpacity),
            (topHeight, 1),
            (height - bottomHeight, 1),
            (height - bottomHeight * 0.5 * bottomProgress, bottomOpacity),
            (height, canScroll ? 0 : 1),
        ]
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        edgeFade.frame = scrollView.bounds
        let flipped = scrollView.layer?.isGeometryFlipped ?? false
        edgeFade.startPoint = CGPoint(x: 0.5, y: flipped ? 0 : 1)
        edgeFade.endPoint = CGPoint(x: 0.5, y: flipped ? 1 : 0)
        edgeFade.colors = stops.map { NSColor.black.withAlphaComponent($0.1).cgColor }
        edgeFade.locations = stops.map { NSNumber(value: Double(min(1, max(0, $0.0 / height)))) }
        CATransaction.commit()
        if ProcessInfo.processInfo.environment["JOT_DEBUG_LAYOUT"] != nil {
            FileHandle.standardError.write(Data("fade: height \(height) doc \(documentHeight) offset \(offset) canScroll \(canScroll) top \(topProgress) bottom \(bottomProgress) mask \(scrollView.layer?.mask === edgeFade) flipped \(flipped)\n".utf8))
        }
    }

    /// Raycast's `[window-hovered]` state, including `NSWindow+TrafficLightButtonsHiding`.
    private func setHovered(_ hovered: Bool) {
        isHovered = hovered
        topBar.setHovered(hovered)
        bottomBar.setHovered(hovered)
        let buttons = [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton].compactMap(panel.standardWindowButton)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Layout.chromeFade
            buttons.forEach { $0.animator().alphaValue = hovered ? 1 : 0 }
        }
    }

    // MARK: Editor wiring

    private func wireEditor() {
        editor.onChange = { [weak self] in
            guard let self else { return }
            isDirty = true
            refreshChrome()
            scheduleSave()
            if !findBar.isHidden { runFind(keepIndex: true) }
        }
        editor.onSelectionChange = { [weak self] in
            guard let self else { return }
            bottomBar.update(editor.state)
        }
        editor.attachments = repository.attachments
        editor.onToast = { [weak self] title, message, failed in
            self?.showToast(title, message: message, variant: failed ? .failure : .success)
        }
        editor.onLayout = { [weak self] in
            self?.autoSize(animated: false)
            self?.updateEdgeFade()
        }
        // Raycast holds the window's height while the slash menu shows, then catches up.
        editor.slashMenu.onVisibilityChange = { [weak self] in self?.autoSize(animated: false) }
    }

    private func refreshChrome() {
        topBar.titleLabel.stringValue = editor.blocks.title
        panel.title = editor.blocks.title
        bottomBar.setCounterText(counterText)
        bottomBar.update(editor.state)
    }

    private var counterText: String {
        if showsWords {
            let n = editor.wordCount
            return n == 1 ? "1 word" : "\(n) words"
        }
        let n = editor.characterCount
        return n == 1 ? "1 character" : "\(n) characters"
    }

    /// Raycast's `toast.open({ variant, title })` (see `ToastHost`).
    private func showToast(_ title: String, message: String? = nil, variant: ToastHost.Variant = .success) {
        toasts.show(title, message: message, variant: variant)
    }

    // MARK: Notes

    private func openInitialNote() {
        if let path = ProcessInfo.processInfo.environment["JOT_JSON_FILE"],
           let json = try? String(contentsOfFile: path, encoding: .utf8),
           let blocks = TiptapCodec.decodeString(json) {
            open(repository.create(blocks: blocks))
            return
        }
        if let path = ProcessInfo.processInfo.environment["JOT_TEXT_FILE"],
           let text = try? String(contentsOfFile: path, encoding: .utf8) {
            open(repository.create(blocks: text.split(separator: "\n").map { Block.paragraph(String($0)) }))
            return
        }
        if ProcessInfo.processInfo.environment["JOT_EMPTY"] != nil {
            open(repository.create())
            return
        }
        if ProcessInfo.processInfo.environment["JOT_DEMO"] != nil {
            open(repository.create(blocks: WelcomeNote.showcase))
            return
        }
        if let note = repository.mostRecentlyAccessed() {
            open(note)
        } else {
            open(repository.create(blocks: WelcomeNote.blocks))
        }
    }

    func open(id: String) {
        guard let note = repository.note(id: id) else { return }
        open(note)
    }

    private func open(_ note: Note, recordHistory: Bool = true) {
        flush()
        if recordHistory, let current, current.id != note.id {
            backStack.append(current.id)
            forwardStack.removeAll()
        }
        current = note
        repository.touchAccessed(id: note.id)
        editor.load(note.blocks, caret: note.caretPosition)
        isDirty = false
        refreshChrome()
        if !findBar.isHidden { runFind(keepIndex: false) }
        autoSize(animated: panel.isVisible)
        DispatchQueue.main.async { [weak self] in self?.updateEdgeFade() }
        editor.focus()
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            self?.flush()
        }
    }

    /// Writes pending changes now.
    func flush() {
        saveTask?.cancel()
        guard let current else { return }
        if isDirty {
            repository.save(id: current.id, blocks: editor.blocks, caret: editor.caret)
            isDirty = false
        } else {
            repository.saveCaret(id: current.id, caret: editor.caret)
        }
    }

    // MARK: Showing

    func show() {
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
        editor.focus()
        setHovered(ProcessInfo.processInfo.environment["JOT_HOVER"] != nil || panel.frame.contains(NSEvent.mouseLocation))
        autoSize(animated: false)
        if let menu = ProcessInfo.processInfo.environment["JOT_OPEN_MENU"], !didOpenDebugMenu {
            didOpenDebugMenu = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [self] in
                switch menu {
                case "browse": browseNotes(nil)
                case "format": showFormatMenu(nil)
                case let query where query.hasPrefix("/"): editor.textView.insertText(query, replacementRange: editor.textView.selectedRange())
                default: showActionsMenu(nil)
                }
                let moves = ProcessInfo.processInfo.environment["JOT_MENU_DOWN"].flatMap(Int.init) ?? 0
                for _ in 0..<moves {
                    if menu.hasPrefix("/") { editor.textView.doCommand(by: #selector(NSResponder.moveDown(_:))) }
                    else { menuPanel?.model.move(1) }
                }
            }
        }
        if let y = ProcessInfo.processInfo.environment["JOT_SCROLL"].flatMap(Double.init) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [self] in
                editor.scrollView.contentView.scroll(to: NSPoint(x: 0, y: y))
                editor.scrollView.reflectScrolledClipView(editor.scrollView.contentView)
            }
        }
        if ProcessInfo.processInfo.environment["JOT_DEBUG_LAYOUT"] != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [self] in
                let sv = editor.scrollView, tv = editor.textView
                FileHandle.standardError.write(Data("""
                    scroll frame \(sv.frame) contentInsets \(sv.contentInsets) safeArea \(sv.safeAreaInsets)
                    clip bounds \(sv.contentView.bounds) clip insets \(sv.contentView.contentInsets)
                    text frame in window \(tv.convert(tv.bounds, to: nil)) containerOrigin \(tv.textContainerOrigin) inset \(tv.textContainerInset)

                    """.utf8))
            }
        }
    }

    func toggle() {
        if panel.isVisible && panel.isKeyWindow {
            flush()
            panel.orderOut(nil)
        } else {
            show()
        }
    }

    func windowDidResignKey(_ notification: Notification) { flush() }

    func windowWillClose(_ notification: Notification) { flush() }

    /// ⌘W and the close button hide the notes window, like ⇧⌘N: Jot keeps running in the
    /// background with its shortcut ready, until you quit it.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard sender === panel else { return true }
        flush()
        panel.orderOut(nil)
        return false
    }

    // MARK: Auto-height (Raycast: "height is dynamic until you resize it")

    private func autoSize(animated: Bool) {
        guard isAutoSizing, !isFramePinned, !editor.slashMenu.isVisible, let screen = panel.screen ?? NSScreen.main else { return }
        let desired = editor.contentHeight
        let maxHeight = min(screen.visibleFrame.height * 0.75, 720)
        let height = min(max(desired, panel.minSize.height), maxHeight).rounded()
        guard abs(panel.frame.height - height) > 1 else { return }
        var frame = panel.frame
        frame.origin.y = frame.maxY - height
        frame.size.height = height
        isResizingProgrammatically = true
        panel.setFrame(frame, display: true, animate: animated)
        isResizingProgrammatically = false
    }

    func windowWillStartLiveResize(_ notification: Notification) {
        if !isResizingProgrammatically, !isFramePinned { isAutoSizing = false }
    }

    // MARK: Commands — notes

    @objc func newNote(_ sender: Any?) {
        if current != nil, editor.plainText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            show()
            return
        }
        flush()
        open(repository.create())
        show()
    }

    @objc func deleteNote(_ sender: Any?) {
        guard let current else { return }
        saveTask?.cancel()
        repository.delete(id: current.id)
        self.current = nil
        if let next = repository.list().first { open(next, recordHistory: false) } else { open(repository.create(), recordHistory: false) }
        showToast("Note deleted")
    }

    @objc func deleteAllNotes(_ sender: Any?) {
        let alert = NSAlert()
        alert.messageText = "Delete All Notes?"
        alert.informativeText = "All notes will move to Recently Deleted, where they can be restored."
        alert.addButton(withTitle: "Delete").hasDestructiveAction = true
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: panel) { [weak self] response in
            guard response == .alertFirstButtonReturn, let self else { return }
            saveTask?.cancel()
            repository.deleteAll()
            current = nil
            open(repository.create(), recordHistory: false)
        }
    }

    @objc func duplicateNote(_ sender: Any?) {
        guard !editor.plainText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        flush()
        open(repository.create(blocks: editor.blocks))
        showToast("Note duplicated")
    }

    @objc func togglePin(_ sender: Any?) {
        guard let current else { return }
        flush()
        repository.setPinned(id: current.id, !current.isPinned)
        self.current = repository.note(id: current.id)
        showToast(current.isPinned ? "Unpinned Note" : "Pinned Note")
    }

    @objc func goBack(_ sender: Any?) {
        guard let id = backStack.popLast(), let note = repository.note(id: id), note.deletedAt == nil else { return }
        if let current { forwardStack.append(current.id) }
        open(note, recordHistory: false)
    }

    @objc func goForward(_ sender: Any?) {
        guard let id = forwardStack.popLast(), let note = repository.note(id: id), note.deletedAt == nil else { return }
        if let current { backStack.append(current.id) }
        open(note, recordHistory: false)
    }

    @objc func moveListItemUp(_ sender: Any?) { editor.moveListItem(up: true) }
    @objc func moveListItemDown(_ sender: Any?) { editor.moveListItem(up: false) }

    // MARK: Copy & export

    private enum ExportFormat: CaseIterable {
        case markdown, html, plainText

        var title: String {
            switch self {
            case .markdown: "Markdown"
            case .html: "HTML"
            case .plainText: "Plain Text"
            }
        }

        var icon: String {
            switch self {
            case .markdown: "brand-markdown"
            case .html: "code"
            case .plainText: "text"
            }
        }

        var fileExtension: String {
            switch self {
            case .markdown: "md"
            case .html: "html"
            case .plainText: "txt"
            }
        }
    }

    private func render(_ format: ExportFormat) -> String {
        let blocks = editor.selectedBlocks ?? editor.blocks
        return switch format {
        case .markdown: MarkdownExporter.markdown(blocks)
        case .html: HTMLExporter.html(blocks)
        case .plainText: blocks.plainText
        }
    }

    private func copy(_ format: ExportFormat) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(render(format), forType: .string)
        showToast("Copied as \(format.title)")
    }

    private func export(_ format: ExportFormat) {
        let save = NSSavePanel()
        save.allowedContentTypes = [UTType(filenameExtension: format.fileExtension) ?? .plainText]
        save.nameFieldStringValue = editor.blocks.title + "." + format.fileExtension
        save.beginSheetModal(for: panel) { [weak self] response in
            guard response == .OK, let url = save.url, let self else { return }
            let blocks = editor.blocks
            let text = switch format {
            case .markdown: MarkdownExporter.markdown(blocks)
            case .html: HTMLExporter.html(blocks)
            case .plainText: blocks.plainText
            }
            try? text.write(to: url, atomically: true, encoding: .utf8)
            showToast("Exported as \(format.title)")
        }
    }

    @objc func copyMarkdown(_ sender: Any?) { copy(.markdown) }
    @objc func copyNoteAs(_ sender: Any?) { presentMenu(copyAsPage) }
    @objc func exportNote(_ sender: Any?) { presentMenu(exportPage) }
    @objc func showFormatMenu(_ sender: Any?) { presentMenu(formatPage) }

    @objc func copyDeeplink(_ sender: Any?) {
        guard let current else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("jot://notes/\(current.id)", forType: .string)
        showToast("Copied Deeplink")
    }

    // MARK: Action Panel (⌘K) & Browse Notes (⌘P) — Raycast's `mr()` and `ar` menus

    private func presentMenu(_ page: MenuPage) {
        if let menuPanel, menuPanel.isVisible { menuPanel.dismiss() }
        flush()
        show()
        let menu = CommandMenuPanel(page: page)
        menu.onDismiss = { [weak self, weak menu] in
            if self?.menuPanel === menu { self?.menuPanel = nil }
            self?.editor.focus()
        }
        menuPanel = menu
        menu.present(over: panel)
    }

    @objc func showActionsMenu(_ sender: Any?) {
        if let menuPanel, menuPanel.isVisible { menuPanel.dismiss(); return }
        presentMenu(actionPage)
    }

    @objc func browseNotes(_ sender: Any?) {
        if let menuPanel, menuPanel.isVisible { menuPanel.dismiss(); return }
        presentMenu(browsePage)
    }

    @objc func showRecentlyDeleted(_ sender: Any?) { presentMenu(recentlyDeletedPage) }

    @objc func addImage(_ sender: Any?) { editor.chooseImages() }

    private var actionPage: MenuPage {
        let isEmpty = editor.plainText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let isPinned = current?.isPinned == true
        let inList = editor.isInListItem
        func item(_ id: String, _ title: String, _ icon: String, _ keys: [String], disabled: Bool = false, destructive: Bool = false, _ action: @escaping () -> Void) -> MenuItem {
            MenuItem(id: id, title: title, icon: icon, shortcut: keys, isDisabled: disabled, isDestructive: destructive, action: action)
        }
        var copyAs = item("copy-note-as", editor.selectedBlocks == nil ? "Copy Note As…" : "Copy Selection As…", "copy-clipboard", ["⇧", "⌘", "C"]) {}
        copyAs.submenu = copyAsPage
        var export = item("export", "Export…", "upload", ["⇧", "⌘", "E"]) {}
        export.submenu = exportPage
        var format = item("format", "Format…", "text", ["⇧", "⌘", ","]) {}
        format.submenu = formatPage
        // Raycast's `image` section, shown while an image is selected.
        let imageSection: [MenuSection] = editor.selectedImage == nil ? [] : [
            MenuSection(id: "image", items: [
                item("image-quick-look", "Quick Look", "eye", ["␣"]) { [weak self] in
                    DispatchQueue.main.async { self?.editor.quickLook() }
                },
                item("image-copy", "Copy Image", "copy-clipboard", ["⌘", "C"]) { [weak self] in self?.editor.copySelectedImage() },
                item("image-save", "Save Image As…", "save-document", []) { [weak self] in
                    DispatchQueue.main.async { self?.editor.saveSelectedImage() }
                },
            ]),
        ]
        return MenuPage(placeholder: "Search for actions…", sections: imageSection + [
            MenuSection(id: "note-management", items: [
                item("new", "New Note", "plus", ["⌘", "N"], disabled: isEmpty) { [weak self] in self?.newNote(nil) },
                item("duplicate", "Duplicate Note", "duplicate", ["⌘", "D"], disabled: isEmpty) { [weak self] in self?.duplicateNote(nil) },
                item("toggle-pin", isPinned ? "Unpin Note" : "Pin Note", isPinned ? "tack-disabled" : "tack", ["⇧", "⌘", "P"]) { [weak self] in self?.togglePin(nil) },
                item("browse", "Browse Notes", "docs-stacked", ["⌘", "P"]) { [weak self] in
                    DispatchQueue.main.async { self?.presentMenu(self?.browsePage ?? MenuPage(placeholder: "", sections: [])) }
                },
                item("go-back", "Go Back", "arrow-left-circle", ["⌘", "["], disabled: backStack.isEmpty) { [weak self] in self?.goBack(nil) },
                item("go-forward", "Go Forward", "arrow-right-circle", ["⌘", "]"], disabled: forwardStack.isEmpty) { [weak self] in self?.goForward(nil) },
            ]),
            MenuSection(id: "copy-export", items: [
                item("find", "Find in Note", "find", ["⌘", "F"]) { [weak self] in self?.showFind(nil) },
                copyAs,
                item("copy-deeplink", "Copy Deeplink", "copy-clipboard", ["⇧", "⌘", "D"]) { [weak self] in self?.copyDeeplink(nil) },
                export,
            ]),
            MenuSection(id: "editing", items: [
                item("move-list-item-up", "Move List Item Up", "arrow-up", ["⌃", "⌘", "↑"], disabled: !inList) { [weak self] in self?.moveListItemUp(nil) },
                item("move-list-item-down", "Move List Item Down", "arrow-down", ["⌃", "⌘", "↓"], disabled: !inList) { [weak self] in self?.moveListItemDown(nil) },
                item("add-image", "Add Image…", "image", ["⇧", "⌘", "I"]) { [weak self] in
                    DispatchQueue.main.async { self?.editor.chooseImages() }
                },
                format,
            ]),
            MenuSection(id: "window-settings", items: [
                item("toggle-auto-sizing", isAutoSizing ? "Disable Window Auto-Sizing" : "Enable Window Auto-Sizing", "app-window", ["⇧", "⌘", "/"]) { [weak self] in self?.toggleAutoSize(nil) },
                item("toggle-format-bar", "Toggle Format Bar", "text", ["⌥", "⌘", ","]) { [weak self] in self?.toggleFormatBar(nil) },
                item("toggle-screen-sharing", ScreenSharing.isHidden ? "Show in Screen Sharing" : "Hide from Screen Sharing",
                     ScreenSharing.isHidden ? "eye" : "eye-disabled", []) { [weak self] in self?.toggleScreenSharing(nil) },
            ]),
            MenuSection(id: "zoom", items: [
                item("actual-size", "Actual Size", "magnifying-glass-one", ["⌘", "0"], disabled: zoom == 1) { [weak self] in self?.resetZoom(nil) },
                item("zoom-in", "Zoom In", "magnifying-glass-plus", ["⌘", "="], disabled: zoom >= Self.zoomRange.upperBound) { [weak self] in self?.zoomIn(nil) },
                item("zoom-out", "Zoom Out", "magnifying-glass-minus", ["⌘", "-"], disabled: zoom <= Self.zoomRange.lowerBound) { [weak self] in self?.zoomOut(nil) },
            ]),
            MenuSection(id: "note-actions-destructive", items: [
                item("recently-deleted", "Show Recently Deleted Notes", "trash", []) { [weak self] in
                    DispatchQueue.main.async { self?.showRecentlyDeleted(nil) }
                },
                item("delete", "Delete Note", "trash", ["⌃", "X"], destructive: true) { [weak self] in self?.deleteNote(nil) },
                item("delete-all", "Delete All Notes", "trash", ["⌃", "⇧", "X"], destructive: true) { [weak self] in self?.deleteAllNotes(nil) },
            ]),
        ], separators: true)
    }

    private var copyAsPage: MenuPage {
        MenuPage(placeholder: editor.selectedBlocks == nil ? "Copy Note As…" : "Copy Selection As…", sections: [
            MenuSection(id: "copy-formats", items: ExportFormat.allCases.map { format in
                MenuItem(id: "copy-\(format)", title: format.title, icon: format.icon) { [weak self] in self?.copy(format) }
            }),
        ])
    }

    private var exportPage: MenuPage {
        MenuPage(placeholder: "Export…", sections: [
            MenuSection(id: "export-formats", items: ExportFormat.allCases.map { format in
                MenuItem(id: "export-\(format)", title: format.title, icon: format.icon) { [weak self] in
                    DispatchQueue.main.async { self?.export(format) }
                }
            }),
        ])
    }

    /// Raycast's "Format…" submenu: Inline / Block / List, searchable as "Format as…".
    private var formatPage: MenuPage {
        let state = editor.state
        func run(_ selector: Selector) -> () -> Void { { [weak self] in NSApp.sendAction(selector, to: self, from: nil) } }
        var heading = MenuItem(id: "format-heading", title: "Heading…", icon: "heading")
        heading.submenu = MenuPage(placeholder: "Heading…", sections: [MenuSection(id: "heading-options", items: [
            MenuItem(id: "h1", title: "Heading 1", icon: "heading", shortcut: ["⌥", "⌘", "1"], isChecked: state.block == .heading1, action: run(#selector(setHeading1(_:)))),
            MenuItem(id: "h2", title: "Heading 2", icon: "heading", shortcut: ["⌥", "⌘", "2"], isChecked: state.block == .heading2, action: run(#selector(setHeading2(_:)))),
            MenuItem(id: "h3", title: "Heading 3", icon: "heading", shortcut: ["⌥", "⌘", "3"], isChecked: state.block == .heading3, action: run(#selector(setHeading3(_:)))),
        ])])
        return MenuPage(placeholder: "Format as…", sections: [
            MenuSection(id: "inline", title: "Inline", items: [
                heading,
                MenuItem(id: "format-bold", title: "Bold", icon: "bold", shortcut: ["⌘", "B"], action: run(#selector(toggleBold(_:)))),
                MenuItem(id: "format-italic", title: "Italic", icon: "italics", shortcut: ["⌘", "I"], action: run(#selector(toggleItalic(_:)))),
                MenuItem(id: "format-strike", title: "Strikethrough", icon: "strike-through", shortcut: ["⇧", "⌘", "S"], action: run(#selector(toggleStrike(_:)))),
                MenuItem(id: "format-underline", title: "Underline", icon: "underline", shortcut: ["⌘", "U"], action: run(#selector(toggleUnderline(_:)))),
                MenuItem(id: "format-code", title: "Code", icon: "code", shortcut: ["⌘", "E"], action: run(#selector(toggleInlineCode(_:)))),
                MenuItem(id: "format-link", title: "Link", icon: "link", shortcut: ["⌘", "L"], action: run(#selector(editLink(_:)))),
            ]),
            MenuSection(id: "block", title: "Block", items: [
                MenuItem(id: "format-quote", title: "Quote", icon: "quote-block", shortcut: ["⇧", "⌘", "B"], action: run(#selector(toggleQuote(_:)))),
                MenuItem(id: "format-code-block", title: "Code Block", icon: "code-block", shortcut: ["⌥", "⌘", "C"], action: run(#selector(toggleCodeBlock(_:)))),
            ]),
            MenuSection(id: "list", title: "List", items: [
                MenuItem(id: "format-bullet", title: "Bulleted List", icon: "bullet-points", shortcut: ["⇧", "⌘", "8"], action: run(#selector(toggleBulletList(_:)))),
                MenuItem(id: "format-ordered", title: "Numbered List", icon: "number-list", shortcut: ["⇧", "⌘", "7"], action: run(#selector(toggleOrderedList(_:)))),
                MenuItem(id: "format-task", title: "Task List", icon: "check-list", shortcut: ["⇧", "⌘", "9"], action: run(#selector(toggleTaskList(_:)))),
            ]),
        ])
    }

    private static let relative: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter
    }()

    private func characters(_ note: Note) -> String {
        let count = note.id == current?.id ? editor.characterCount : note.text.trimmingCharacters(in: .whitespacesAndNewlines).count
        return count == 1 ? "1 character" : "\(count) characters"
    }

    /// Raycast's `ar` browse menu: "Search for notes…", a count header, Pinned then Notes,
    /// "Current • N characters" with an accent dot, "Opened <relative> • N characters".
    private var browsePage: MenuPage {
        let notes = repository.list()
        func row(_ note: Note) -> MenuItem {
            let isCurrent = note.id == current?.id
            let subtitle = isCurrent
                ? "Current • \(characters(note))"
                : "Opened \(Self.relative.localizedString(for: note.lastAccessedAt, relativeTo: .now)) • \(characters(note))"
            return MenuItem(
                id: note.id, title: note.title, subtitle: subtitle, subtitleDot: isCurrent, keywords: [note.text],
                trailingButton: .init(icon: "trash", tooltip: "Delete Note") { [weak self] in
                    self?.menuPanel?.dismiss()
                    self?.repository.delete(id: note.id)
                    if note.id == self?.current?.id { self?.deleteNote(nil) }
                },
                action: { [weak self] in self?.open(id: note.id) }
            )
        }
        let pinned = notes.filter(\.isPinned).map(row)
        let others = notes.filter { !$0.isPinned }.map(row)
        var page = MenuPage(placeholder: "Search for notes…", headerTitle: notes.count == 1 ? "1 Note" : "\(notes.count) Notes", sections: [
            MenuSection(id: "pinned", title: "Pinned", items: pinned),
            MenuSection(id: "notes", title: "Notes", items: others),
        ], rowStyle: .multiline)
        page.emptyText = "No Notes"
        return page
    }

    private var recentlyDeletedPage: MenuPage {
        let notes = repository.listDeleted()
        var page = MenuPage(placeholder: "Search for deleted notes…", sections: [
            MenuSection(id: "deleted", title: "Recently Deleted", items: notes.map { note in
                MenuItem(
                    id: note.id, title: note.title,
                    subtitle: "Deleted \(Self.relative.localizedString(for: note.deletedAt ?? .now, relativeTo: .now)) • \(characters(note))",
                    keywords: [note.text],
                    action: { [weak self] in
                        self?.repository.restore(id: note.id)
                        self?.open(id: note.id)
                        self?.showToast("Note Restored")
                    }
                )
            }),
        ], rowStyle: .multiline)
        page.emptyText = "No Recently Deleted Notes"
        return page
    }

    // MARK: Commands — formatting

    @objc func toggleBold(_ sender: Any?) { editor.toggleMark(.bold) }
    @objc func toggleItalic(_ sender: Any?) { editor.toggleMark(.italic) }
    @objc func toggleUnderline(_ sender: Any?) { editor.toggleMark(.underline) }
    @objc func toggleStrike(_ sender: Any?) { editor.toggleMark(.strike) }
    @objc func toggleInlineCode(_ sender: Any?) { editor.toggleMark(.code) }
    @objc func setHeading1(_ sender: Any?) { editor.toggleBlock(.heading1) }
    @objc func setHeading2(_ sender: Any?) { editor.toggleBlock(.heading2) }
    @objc func setHeading3(_ sender: Any?) { editor.toggleBlock(.heading3) }
    @objc func setBody(_ sender: Any?) { editor.toggleBlock(.paragraph) }
    @objc func toggleBulletList(_ sender: Any?) { editor.toggleBlock(.bullet) }
    @objc func toggleOrderedList(_ sender: Any?) { editor.toggleBlock(.ordered) }
    @objc func toggleTaskList(_ sender: Any?) { editor.toggleBlock(.task) }
    @objc func toggleQuote(_ sender: Any?) { editor.toggleBlock(.quote) }
    @objc func toggleCodeBlock(_ sender: Any?) { editor.toggleBlock(.code) }
    @objc func toggleTask(_ sender: Any?) { editor.toggleTask() }
    @objc func insertRule(_ sender: Any?) { editor.insertRule() }

    @objc func editLink(_ sender: Any?) {
        let (href, range) = editor.currentLink()
        let textView = editor.textView
        var rect = NSRect(origin: .zero, size: NSSize(width: 1, height: 1))
        let screenRect = textView.firstRect(forCharacterRange: range, actualRange: nil)
        if let window = textView.window, !screenRect.isEmpty || screenRect.origin != .zero {
            rect = textView.convert(window.convertFromScreen(screenRect), from: nil)
        }
        linkPopover.show(relativeTo: rect, of: textView, href: href) { [weak self] value in
            self?.editor.setLink(value, range: range)
            self?.editor.focus()
        }
    }

    @objc func showHeadingMenu(_ sender: Any?) {
        let block = editor.state.block
        let menu = NSMenu()
        for (title, kind, action, key) in [
            ("Heading 1", BlockKind.heading1, #selector(setHeading1(_:)), "1"),
            ("Heading 2", .heading2, #selector(setHeading2(_:)), "2"),
            ("Heading 3", .heading3, #selector(setHeading3(_:)), "3"),
        ] {
            let entry = item(title, action, key, [.command, .option])
            entry.state = block == kind ? .on : .off
            menu.addItem(entry)
        }
        popUp(menu, from: sender)
    }

    @objc func showListMenu(_ sender: Any?) {
        let block = editor.state.block
        let menu = NSMenu()
        for (title, kind, action, key) in [
            ("Bulleted List", BlockKind.bullet, #selector(toggleBulletList(_:)), "8"),
            ("Numbered List", .ordered, #selector(toggleOrderedList(_:)), "7"),
            ("Task List", .task, #selector(toggleTaskList(_:)), "9"),
        ] {
            let entry = item(title, action, key, [.command, .shift])
            entry.state = block == kind ? .on : .off
            menu.addItem(entry)
        }
        popUp(menu, from: sender)
    }

    @objc func toggleFormatBar(_ sender: Any?) {
        let visible = !bottomBar.isFormatBarVisible
        defaults.set(visible, forKey: "formatBarVisible")
        bottomBar.setFormatBarVisible(visible)
    }

    @objc func toggleCounterMode(_ sender: Any?) {
        showsWords.toggle()
        bottomBar.setCounterText(counterText)
    }

    // MARK: Commands — view

    // Raycast's `notes-zoom`: 75%–200% in 5% steps. Each action is disabled at its limit,
    // so its shortcut does nothing there (and shows no toast).
    static let zoomRange: ClosedRange<CGFloat> = 0.75...2

    @objc func zoomIn(_ sender: Any?) {
        guard zoom < Self.zoomRange.upperBound else { return }
        setZoom(zoom + 0.05)
    }

    @objc func zoomOut(_ sender: Any?) {
        guard zoom > Self.zoomRange.lowerBound else { return }
        setZoom(zoom - 0.05)
    }

    @objc func resetZoom(_ sender: Any?) {
        guard zoom != 1 else { return }
        setZoom(1, toastTitle: "Zoom reset to default")
    }

    private func setZoom(_ value: CGFloat, toastTitle: String? = nil) {
        let clamped = min(Self.zoomRange.upperBound, max(Self.zoomRange.lowerBound, (value * 20).rounded() / 20))
        zoom = clamped
        editor.style.zoom = clamped
        showToast(toastTitle ?? "Zoomed to \(Int((clamped * 100).rounded()))%")
    }

    @objc func toggleAutoSize(_ sender: Any?) {
        isAutoSizing.toggle()
        autoSize(animated: true)
    }

    var onShowSettings: (() -> Void)?

    @objc func showSettings(_ sender: Any?) { onShowSettings?() }

    /// Keeps Jot out of screen shares, recordings and screenshots (see `ScreenSharing`).
    @objc func toggleScreenSharing(_ sender: Any?) {
        ScreenSharing.isHidden.toggle()
        showToast(ScreenSharing.isHidden ? "Hidden from Screen Sharing" : "Visible in Screen Sharing")
    }

    // MARK: Find & replace

    @objc func showFind(_ sender: Any?) {
        show()
        let selection = editor.textView.selectedRange()
        if selection.length > 0 {
            findBar.findField.stringValue = (editor.text as NSString).substring(with: selection)
        }
        if findBar.isHidden {
            findBar.isHidden = false
            editor.verticalInset = Self.chromeInset + 48
            autoSize(animated: false)
        }
        panel.makeFirstResponder(findBar.findField)
        findBar.findField.selectText(nil)
        runFind(keepIndex: false)
    }

    private func hideFind() {
        findBar.isHidden = true
        findMatches = []
        findIndex = nil
        editor.setFindHighlights([], active: nil)
        editor.verticalInset = Self.chromeInset
        autoSize(animated: false)
        editor.focus()
    }

    private func runFind(keepIndex: Bool) {
        let query = findBar.findField.stringValue
        findMatches = []
        if !query.isEmpty {
            let text = editor.text as NSString
            var range = NSRange(location: 0, length: text.length)
            while true {
                let found = text.range(of: query, options: [.caseInsensitive, .diacriticInsensitive], range: range)
                if found.location == NSNotFound { break }
                findMatches.append(found)
                range = NSRange(location: NSMaxRange(found), length: text.length - NSMaxRange(found))
            }
        }
        if findMatches.isEmpty {
            findIndex = nil
        } else if !keepIndex || findIndex == nil {
            let caret = editor.textView.selectedRange().location
            findIndex = findMatches.firstIndex { $0.location >= caret } ?? 0
        } else {
            findIndex = min(findIndex ?? 0, findMatches.count - 1)
        }
        editor.setFindHighlights(findMatches, active: findIndex)
        findBar.setCount(current: findIndex, total: findMatches.count)
    }

    private func stepFind(_ delta: Int) {
        guard !findMatches.isEmpty else { return }
        findIndex = ((findIndex ?? -delta) + delta + findMatches.count) % findMatches.count
        editor.setFindHighlights(findMatches, active: findIndex)
        findBar.setCount(current: findIndex, total: findMatches.count)
    }

    private func replaceCurrent(with replacement: String) {
        guard let findIndex, findMatches.indices.contains(findIndex) else { return }
        editor.replaceText(in: [findMatches[findIndex]], with: replacement)
        runFind(keepIndex: true)
    }

    private func replaceAll(with replacement: String) {
        guard !findMatches.isEmpty else { return }
        editor.replaceText(in: findMatches, with: replacement)
        runFind(keepIndex: false)
    }

    // MARK: Menu helpers

    private func item(_ title: String, _ action: Selector, _ key: String, _ modifiers: NSEvent.ModifierFlags = .command) -> NSMenuItem {
        let entry = NSMenuItem(title: title, action: action, keyEquivalent: key)
        entry.keyEquivalentModifierMask = modifiers
        entry.target = self
        return entry
    }

    private func popUp(_ menu: NSMenu, from sender: Any?) {
        if let view = sender as? NSView {
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: view.bounds.height + 6), in: view)
        } else {
            let caret = editor.textView.firstRect(forCharacterRange: editor.textView.selectedRange(), actualRange: nil)
            menu.popUp(positioning: nil, at: NSPoint(x: caret.minX, y: caret.minY), in: nil)
        }
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(togglePin(_:)):
            menuItem.title = current?.isPinned == true ? "Unpin Note" : "Pin Note"
        case #selector(toggleAutoSize(_:)):
            menuItem.state = isAutoSizing ? .on : .off
        case #selector(toggleScreenSharing(_:)):
            menuItem.state = ScreenSharing.isHidden ? .on : .off
        case #selector(toggleFormatBar(_:)):
            menuItem.title = bottomBar.isFormatBarVisible ? "Hide Format Bar" : "Show Format Bar"
        case #selector(resetZoom(_:)):
            return zoom != 1
        case #selector(zoomIn(_:)):
            return zoom < Self.zoomRange.upperBound
        case #selector(zoomOut(_:)):
            return zoom > Self.zoomRange.lowerBound
        default:
            break
        }
        return true
    }
}
