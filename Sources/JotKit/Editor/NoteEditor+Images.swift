import AppKit
import UniformTypeIdentifiers

/// Image blocks, built from the image design Raycast ships switched off (its `image` node,
/// `.imageBlock` CSS and Quick Look wiring), with the files kept locally.
extension NoteEditor {
    /// Raycast's limit for one image.
    nonisolated static let maxImageBytes = 20 * 1024 * 1024

    enum ImageSource: Sendable {
        case file(URL)
        case data(Data)
    }

    // MARK: Finding and selecting

    func range(of attachment: ImageAttachment) -> NSRange? {
        var found: NSRange?
        storage.enumerateAttribute(.attachment, in: NSRange(location: 0, length: storage.length)) { value, range, stop in
            if (value as? ImageAttachment) === attachment {
                found = range
                stop.pointee = true
            }
        }
        return found
    }

    /// The image whose block is selected (ProseMirror's `NodeSelection`): exactly its character.
    var selectedImage: ImageAttachment? {
        let selection = textView.selectedRange()
        guard selection.length == 1, selection.location < storage.length else { return nil }
        return storage.attribute(.attachment, at: selection.location, effectiveRange: nil) as? ImageAttachment
    }

    func select(_ attachment: ImageAttachment) {
        guard let range = range(of: attachment) else { return }
        textView.window?.makeFirstResponder(textView)
        textView.setSelectedRange(range)
    }

    /// Selects the image block that starts at `location`.
    private func selectImage(atParagraph location: Int) {
        textView.setSelectedRange(NSRange(location: location, length: 1))
    }

    // MARK: Geometry & drawing

    /// Where an image is drawn, in text view coordinates.
    func imageFrame(for attachment: ImageAttachment) -> CGRect? {
        guard let range = range(of: attachment),
              let start = textRange(NSRange(location: range.location, length: 0))?.location,
              let fragment = layoutManager.textLayoutFragment(for: start)
        else { return nil }
        let frame = fragment.frameForTextAttachment(at: start)
        guard !frame.isEmpty else { return nil }
        let origin = textView.textContainerOrigin
        return frame.offsetBy(dx: fragment.layoutFragmentFrame.minX + origin.x, dy: fragment.layoutFragmentFrame.minY + origin.y)
    }

    /// The image under a point in text view coordinates.
    func image(at point: CGPoint) -> ImageAttachment? {
        let origin = textView.textContainerOrigin
        let local = CGPoint(x: max(0, point.x - origin.x), y: point.y - origin.y)
        guard let fragment = layoutManager.textLayoutFragment(for: local),
              let range = nsRange(fragment.rangeInElement),
              range.length > 0, range.location < storage.length,
              let attachment = storage.attribute(.attachment, at: range.location, effectiveRange: nil) as? ImageAttachment,
              let frame = imageFrame(for: attachment), frame.contains(point)
        else { return nil }
        return attachment
    }

    var selectedImageScreenFrame: CGRect {
        guard let image = selectedImage, let frame = imageFrame(for: image), let window = textView.window else { return .zero }
        return window.convertToScreen(textView.convert(frame, to: nil))
    }

    /// The selected image as it's shown, for Quick Look's zoom and drag images.
    func snapshot(of attachment: ImageAttachment) -> NSImage? {
        guard let frame = imageFrame(for: attachment), let url = attachments?.url(for: attachment.ref.attachmentId) else { return nil }
        let scale = textView.window?.backingScaleFactor ?? 2
        let pixels = ImageCache.bucket(max(frame.width, frame.height) * scale)
        guard let image = ImageCache.shared.cached(url, maxPixels: pixels) else { return nil }
        return NSImage(cgImage: image, size: frame.size)
    }

    /// Redraws the blocks of the given image ids (or of `attachment`).
    func redrawImages(where matches: (ImageAttachment) -> Bool) {
        storage.enumerateAttribute(.attachment, in: NSRange(location: 0, length: storage.length)) { value, range, _ in
            guard let attachment = value as? ImageAttachment, matches(attachment),
                  let textRange = textRange(paragraphRange(at: range.location))
            else { return }
            layoutManager.invalidateLayout(for: textRange)
        }
        // Lay the visible text out again now; otherwise the redraw waits for the next keystroke.
        layoutManager.textViewportLayoutController.layoutViewport()
        textView.needsDisplay = true
    }

    @objc func imageDecoded(_ notification: Notification) {
        guard let id = notification.object as? String else { return }
        redrawImages { $0.ref.attachmentId == id }
    }

    /// Keeps each attachment's `isSelected` in step with the text selection.
    func updateImageSelection() {
        let selected = selectedImage
        var changed: [ImageAttachment] = []
        storage.enumerateAttribute(.attachment, in: NSRange(location: 0, length: storage.length)) { value, _, _ in
            guard let attachment = value as? ImageAttachment else { return }
            let isSelected = attachment === selected
            if attachment.isSelected != isSelected {
                attachment.isSelected = isSelected
                changed.append(attachment)
            }
        }
        if !changed.isEmpty { redrawImages { image in changed.contains { $0 === image } } }
    }

    // MARK: Mouse

    /// Click selects an image, double-click opens Quick Look, dragging moves it.
    func handleImageMouseDown(_ event: NSEvent) -> Bool {
        let point = textView.convert(event.locationInWindow, from: nil)
        guard let attachment = image(at: point) else { return false }
        select(attachment)
        if event.clickCount == 2 {
            quickLook()
            return true
        }
        guard let window = textView.window else { return true }
        while let next = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            if next.type == .leftMouseUp { break }
            let a = event.locationInWindow, b = next.locationInWindow
            if hypot(b.x - a.x, b.y - a.y) > 4 {
                beginImageDrag(attachment, event: event)
                break
            }
        }
        return true
    }

    private func beginImageDrag(_ attachment: ImageAttachment, event: NSEvent) {
        guard let range = range(of: attachment), let frame = imageFrame(for: attachment) else { return }
        let item = NSPasteboardItem()
        item.setString("\(attachment.ref.attachmentId)|\(range.location)", forType: .jotImageMove)
        if let url = attachments?.url(for: attachment.ref.attachmentId) {
            item.setString(url.absoluteString, forType: .fileURL)
        }
        let dragging = NSDraggingItem(pasteboardWriter: item)
        dragging.setDraggingFrame(frame, contents: snapshot(of: attachment))
        let session = textView.beginDraggingSession(with: [dragging], event: event, source: textView)
        session.animatesToStartingPositionsOnCancelOrFail = true
    }

    /// The image being moved by a drag from this note, from its pasteboard id and position.
    private func movingImage(_ info: any NSDraggingInfo) -> ImageAttachment? {
        guard (info.draggingSource as AnyObject?) === textView,
              let value = info.draggingPasteboard.string(forType: .jotImageMove)
        else { return nil }
        let parts = value.split(separator: "|")
        guard parts.count == 2, let location = Int(parts[1]), location < storage.length,
              let attachment = storage.attribute(.attachment, at: location, effectiveRange: nil) as? ImageAttachment,
              attachment.ref.attachmentId == parts[0]
        else { return nil }
        return attachment
    }

    var selectedImageURL: URL? {
        selectedImage.flatMap { attachments?.url(for: $0.ref.attachmentId) }
    }

    // MARK: Adding

    /// Validates and stores images off the main thread, then inserts one block per image
    /// (Raycast's `Up`): at `location` (a block boundary, for drops) or at the selection.
    func addImages(_ sources: [ImageSource], at location: Int? = nil) {
        guard let store = attachments, !sources.isEmpty else { return }
        // Decoded before the blocks go in, at the size they'll be drawn, so they appear at once.
        let available = textView.textContainer?.size.width ?? 480
        let scale = textView.window?.backingScaleFactor ?? 2
        Task {
            let results = await Self.store(sources, in: store, warmingFor: available, scale: scale)
            let refs = results.compactMap { $0 }
            let failed = results.count - refs.count
            if failed > 0 {
                onToast?(failed == results.count ? "Couldn't add images" : "Some files couldn't be added",
                         "Select readable, supported images up to 20 MB.", true)
            }
            guard !refs.isEmpty else { return }
            if let location {
                insertImageBlocks(refs, atBlockBoundary: min(location, storage.length))
            } else {
                insertImageBlocksAtSelection(refs)
            }
        }
    }

    @concurrent
    private static func store(_ sources: [ImageSource], in store: AttachmentStore, warmingFor available: CGFloat, scale: CGFloat) async -> [ImageRef?] {
        var refs: [ImageRef?] = []
        for source in sources {
            let ref: ImageRef?
            switch source {
            case .file(let url):
                let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                ref = size > 0 && size <= maxImageBytes ? try? store.add(contentsOf: url) : nil
            case .data(let data):
                ref = !data.isEmpty && data.count <= maxImageBytes ? try? store.add(data) : nil
            }
            if let ref, let url = store.url(for: ref.attachmentId) {
                let size = ImageAttachment.displaySize(ref, available: available)
                _ = await ImageCache.shared.image(url, maxPixels: ImageCache.bucket(max(size.width, size.height) * scale))
            }
            refs.append(ref)
        }
        return refs
    }

    private func imageBlocks(_ refs: [ImageRef]) -> NSAttributedString {
        DocumentCodec.attributedString(refs.map(Block.image))
    }

    /// Inserts at a paragraph boundary and selects the last image (a dropped node is selected).
    func insertImageBlocks(_ refs: [ImageRef], atBlockBoundary location: Int) {
        let boundary = location >= storage.length ? storage.length : paragraphRange(at: location).location
        let images = imageBlocks(refs)
        grouped { replace(NSRange(location: boundary, length: 0), with: images) }
        selectImage(atParagraph: boundary + images.length - 2)
    }

    /// At the caret: an empty paragraph is replaced; otherwise the paragraph splits around the
    /// images. A paragraph follows them for the caret, unless there's already text after.
    func insertImageBlocksAtSelection(_ refs: [ImageRef]) {
        var selection = textView.selectedRange()
        grouped {
            if let image = selectedImage, let range = range(of: image) {
                selection = NSRange(location: NSMaxRange(paragraphRange(at: range.location)), length: 0)
            } else if isInCodeBlock {
                var end = NSMaxRange(paragraphRange(at: selection.location))
                while end < storage.length, info(at: end).kind == .code { end = NSMaxRange(paragraphRange(at: end)) }
                selection = NSRange(location: end, length: 0)
            } else if selection.length > 0 {
                replace(selection, with: "", attributes: [:])
                selection.length = 0
            }

            let images = imageBlocks(refs)
            let caret = selection.location
            if caret >= storage.length {
                replace(NSRange(location: storage.length, length: 0), with: images)
                textView.setSelectedRange(NSRange(location: storage.length, length: 0))
                return
            }
            let paragraph = paragraphRange(at: caret)
            let content = contentRange(paragraph)
            if content.length == 0 {
                // The empty paragraph stays below the images, with the caret in it.
                replace(NSRange(location: paragraph.location, length: 0), with: images)
                textView.setSelectedRange(NSRange(location: paragraph.location + images.length, length: 0))
            } else if caret == content.location {
                replace(NSRange(location: paragraph.location, length: 0), with: images)
                textView.setSelectedRange(NSRange(location: paragraph.location + images.length, length: 0))
            } else if caret == NSMaxRange(content) {
                let after = NSMutableAttributedString(attributedString: images)
                after.append(NSAttributedString(string: "\n", attributes: paragraphAttributes(ParagraphInfo())))
                replace(NSRange(location: NSMaxRange(paragraph), length: 0), with: after)
                textView.setSelectedRange(NSRange(location: NSMaxRange(paragraph) + after.length - 1, length: 0))
            } else {
                // Split: the text before keeps its block, the images go between.
                let info = storage.paragraphInfo(at: paragraph)
                replace(NSRange(location: caret, length: 0), with: "\n", attributes: paragraphAttributes(info))
                replace(NSRange(location: caret + 1, length: 0), with: images)
                textView.setSelectedRange(NSRange(location: caret + 1 + images.length, length: 0))
            }
        }
        updateTypingAttributes()
        textView.scrollRangeToVisible(textView.selectedRange())
    }

    /// ⇧⌘I: Raycast's "Select Images" picker.
    func chooseImages() {
        guard let window = textView.window else { return }
        let panel = NSOpenPanel()
        panel.title = "Select Images"
        panel.prompt = "Add"
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.image]
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK else { return }
            self?.addImages(panel.urls.map(ImageSource.file))
        }
    }

    // MARK: Keys (ProseMirror's NodeSelection behaviour)

    /// Handles a command around image blocks; nil means "not about images".
    func handleImageCommand(_ selector: Selector) -> Bool? {
        if let image = selectedImage, let range = range(of: image) {
            let paragraph = paragraphRange(at: range.location)
            switch selector {
            case #selector(NSResponder.deleteBackward(_:)), #selector(NSResponder.deleteForward(_:)),
                 #selector(NSResponder.deleteWordBackward(_:)), #selector(NSResponder.deleteWordForward(_:)):
                deleteImageBlock(paragraph)
                return true
            case #selector(NSResponder.insertNewline(_:)):
                // `createParagraphNear`: after the image, or before it when it's the first block.
                let at = paragraph.location == 0 ? 0 : NSMaxRange(paragraph)
                grouped { replace(NSRange(location: at, length: 0), with: "\n", attributes: paragraphAttributes(ParagraphInfo())) }
                textView.setSelectedRange(NSRange(location: at, length: 0))
                return true
            case #selector(NSResponder.moveUp(_:)), #selector(NSResponder.moveLeft(_:)):
                leaveImage(paragraph, forward: false)
                return true
            case #selector(NSResponder.moveDown(_:)), #selector(NSResponder.moveRight(_:)):
                leaveImage(paragraph, forward: true)
                return true
            case #selector(NSResponder.insertTab(_:)), #selector(NSResponder.insertBacktab(_:)):
                return true
            default:
                return nil
            }
        }

        let selection = textView.selectedRange()
        guard selection.length == 0, storage.length > 0 else { return nil }
        let paragraph = paragraphRange(at: selection.location)
        let content = contentRange(paragraph)
        switch selector {
        case #selector(NSResponder.deleteBackward(_:)) where selection.location == paragraph.location && paragraph.location > 0:
            // `joinBackward` next to an atom: select it; an empty paragraph goes away.
            let previous = paragraphRange(at: paragraph.location - 1)
            guard info(at: previous.location).kind == .image else { return nil }
            if content.length == 0 { grouped { replace(paragraph, with: "", attributes: [:]) } }
            selectImage(atParagraph: previous.location)
            return true
        case #selector(NSResponder.deleteForward(_:)) where selection.location == NSMaxRange(content) && NSMaxRange(paragraph) < storage.length:
            let next = NSMaxRange(paragraph)
            guard info(at: next).kind == .image else { return nil }
            if content.length == 0 {
                grouped { replace(paragraph, with: "", attributes: [:]) }
                selectImage(atParagraph: paragraph.location)
            } else {
                selectImage(atParagraph: next)
            }
            return true
        default:
            return nil
        }
    }

    private func leaveImage(_ paragraph: NSRange, forward: Bool) {
        if forward {
            let next = NSMaxRange(paragraph)
            guard next < storage.length else { return }
            if info(at: next).kind == .image { selectImage(atParagraph: next) }
            else { textView.setSelectedRange(NSRange(location: next, length: 0)) }
        } else {
            guard paragraph.location > 0 else { return }
            let previous = paragraphRange(at: paragraph.location - 1)
            if info(at: previous.location).kind == .image { selectImage(atParagraph: previous.location) }
            else { textView.setSelectedRange(NSRange(location: paragraph.location - 1, length: 0)) }
        }
        textView.scrollRangeToVisible(textView.selectedRange())
    }

    /// Removes the whole block; the caret goes to the end of the block above (or the start of
    /// the one below), selecting it instead if that's an image too.
    func deleteImageBlock(_ paragraph: NSRange) {
        grouped { replace(paragraph, with: "", attributes: [:]) }
        if paragraph.location > 0 {
            let previous = paragraphRange(at: paragraph.location - 1)
            if info(at: previous.location).kind == .image { selectImage(atParagraph: previous.location) }
            else { textView.setSelectedRange(NSRange(location: paragraph.location - 1, length: 0)) }
        } else if storage.length > 0, info(at: 0).kind == .image {
            selectImage(atParagraph: 0)
        } else {
            textView.setSelectedRange(NSRange(location: 0, length: 0))
        }
    }

    /// Typing over a selected image replaces it with a paragraph of text; Space opens Quick Look.
    func handleTypingOverImage(_ typed: String) -> Bool {
        guard let image = selectedImage, let range = range(of: image) else { return false }
        if typed == " " {
            quickLook()
            return true
        }
        let paragraph = paragraphRange(at: range.location)
        var attributes = paragraphAttributes(ParagraphInfo())
        attributes[.jotMarks] = 0
        grouped { replace(paragraph, with: typed + "\n", attributes: attributes) }
        textView.setSelectedRange(NSRange(location: paragraph.location + typed.utf16.count, length: 0))
        updateTypingAttributes()
        return true
    }

    /// An image block holds exactly its attachment: one that lost it becomes a paragraph, and
    /// text that ended up beside it moves into a paragraph of its own.
    func normalizeImageBlocks() {
        var location = 0
        while location < storage.length {
            let paragraph = paragraphRange(at: location)
            location = NSMaxRange(paragraph)
            guard storage.paragraphInfo(at: paragraph).kind == .image else { continue }
            let content = contentRange(paragraph)
            var attachmentIndex: Int?
            storage.enumerateAttribute(.attachment, in: content) { value, range, stop in
                if value is ImageAttachment { attachmentIndex = range.location; stop.pointee = true }
            }
            guard let index = attachmentIndex else {
                setInfo(ParagraphInfo(), for: [paragraph])
                continue
            }
            guard content.length > 1 else { continue }
            let text = NSMutableAttributedString(attributedString: storage.attributedSubstring(from: content))
            text.deleteCharacters(in: NSRange(location: index - content.location, length: 1))
            let attachment = storage.attributedSubstring(from: NSRange(location: index, length: 1))
            let rebuilt = NSMutableAttributedString(attributedString: attachment)
            rebuilt.append(storage.attributedSubstring(from: NSRange(location: NSMaxRange(content), length: paragraph.length - content.length)))
            let paragraphText = NSMutableAttributedString(attributedString: text)
            paragraphText.addAttributes(ParagraphInfo().attributes, range: NSRange(location: 0, length: paragraphText.length))
            paragraphText.append(NSAttributedString(string: "\n", attributes: paragraphAttributes(ParagraphInfo())))
            rebuilt.append(paragraphText)
            replace(paragraph, with: rebuilt)
            textView.setSelectedRange(NSRange(location: paragraph.location + rebuilt.length - 1, length: 0))
            return
        }
    }

    // MARK: Image actions

    func quickLook() {
        textView.toggleQuickLook()
    }

    @objc func copySelectedImage(_ sender: Any? = nil) {
        guard let image = selectedImage, let url = attachments?.url(for: image.ref.attachmentId) else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let item = NSPasteboardItem()
        item.setString(url.absoluteString, forType: .fileURL)
        if let type = UTType(filenameExtension: url.pathExtension), let data = try? Data(contentsOf: url) {
            item.setData(data, forType: NSPasteboard.PasteboardType(type.identifier))
        }
        item.setString(TiptapCodec.encodeString([.image(image.ref)]), forType: .jotBlocks)
        if !pasteboard.writeObjects([item]) { onToast?("Couldn't copy image", nil, true) }
    }

    @objc func saveSelectedImage(_ sender: Any? = nil) {
        guard let url = selectedImageURL, let window = textView.window else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "image.\(url.pathExtension)"
        if let type = UTType(filenameExtension: url.pathExtension) { panel.allowedContentTypes = [type] }
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let destination = panel.url else { return }
            do {
                if FileManager.default.fileExists(atPath: destination.path) { try FileManager.default.removeItem(at: destination) }
                try FileManager.default.copyItem(at: url, to: destination)
            } catch {
                self?.onToast?("Couldn't save image", nil, true)
            }
        }
    }

    @objc func quickLookSelectedImage(_ sender: Any? = nil) {
        quickLook()
    }

    /// The image's context menu (Raycast: Quick Look, Copy Image, Save As…).
    func imageMenu() -> NSMenu {
        let menu = NSMenu()
        func item(_ title: String, _ symbol: String, _ action: Selector) {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
            menu.addItem(item)
        }
        item("Quick Look", "eye", #selector(quickLookSelectedImage(_:)))
        item("Copy Image", "doc.on.doc", #selector(copySelectedImage(_:)))
        item("Save As…", "square.and.arrow.down", #selector(saveSelectedImage(_:)))
        return menu
    }

    // MARK: Paste

    /// ⌘V. In a code block only text goes in; Jot's own blocks keep their formatting (and
    /// images); image files and image data (screenshots) become image blocks; other text is
    /// read as Markdown.
    func paste(from pasteboard: NSPasteboard) -> Bool {
        if isInCodeBlock, let string = pasteboard.string(forType: .string) {
            paste(plainText: string)
            return true
        }
        if let json = pasteboard.string(forType: .jotBlocks), let blocks = TiptapCodec.decodeString(json) {
            paste(blocks)
            return true
        }
        let files = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        if !files.isEmpty {
            let images = files.filter(Self.isImageFile)
            if !images.isEmpty {
                addImages(images.map(ImageSource.file))
                return true
            }
        } else {
            let datas = (pasteboard.pasteboardItems ?? []).compactMap(Self.imageData)
            if !datas.isEmpty {
                addImages(datas.map(ImageSource.data))
                return true
            }
        }
        if let string = pasteboard.string(forType: .string) {
            paste(MarkdownImporter.blocks(string))
            return true
        }
        return false
    }

    static func isImageFile(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.contentTypeKey]).contentType)?.conforms(to: .image)
            ?? UTType(filenameExtension: url.pathExtension)?.conforms(to: .image) ?? false
    }

    /// Image data Jot can paste, in order of preference: an original format first, TIFF last.
    static let pastedImageTypes: [NSPasteboard.PasteboardType] =
        [UTType.png, .jpeg, .heic, .gif, .webP, .tiff].map { NSPasteboard.PasteboardType($0.identifier) }

    private static func imageData(_ item: NSPasteboardItem) -> Data? {
        pastedImageTypes.lazy.compactMap { item.data(forType: $0) }.first
    }

    // MARK: Drag and drop

    /// A drag of image files, or of an image block, over the text: shows the drop bar at the
    /// nearest gap between blocks and scrolls near the edges. Nil when it's not an image drag.
    func imageDragUpdated(_ info: any NSDraggingInfo) -> NSDragOperation? {
        let isMove = movingImage(info) != nil
        let hasFiles = !isMove && !imageFiles(in: info.draggingPasteboard).isEmpty
        guard isMove || hasFiles else {
            textView.hideDropIndicator()
            return nil
        }
        let point = textView.convert(info.draggingLocation, from: nil)
        autoscrollDuringDrag(at: point)
        let gap = dropGap(at: point.y)
        textView.showDropIndicator(at: gap.y)
        return isMove ? .move : .copy
    }

    func performImageDrop(_ info: any NSDraggingInfo) -> Bool {
        textView.hideDropIndicator()
        let point = textView.convert(info.draggingLocation, from: nil)
        let gap = dropGap(at: point.y)
        if let source = movingImage(info) {
            moveImage(source, to: gap.location)
            return true
        }
        let files = imageFiles(in: info.draggingPasteboard)
        guard !files.isEmpty else { return false }
        addImages(files.map(ImageSource.file), at: gap.location)
        return true
    }

    private func imageFiles(in pasteboard: NSPasteboard) -> [URL] {
        (pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? [])
            .filter(Self.isImageFile)
    }

    private func moveImage(_ attachment: ImageAttachment, to location: Int) {
        guard let range = range(of: attachment) else { return }
        let paragraph = paragraphRange(at: range.location)
        guard location < paragraph.location || location > NSMaxRange(paragraph) else { return }
        let block = storage.attributedSubstring(from: paragraph)
        grouped {
            if location > paragraph.location {
                replace(NSRange(location: location, length: 0), with: block)
                replace(paragraph, with: "", attributes: [:])
            } else {
                replace(paragraph, with: "", attributes: [:])
                replace(NSRange(location: location, length: 0), with: block)
            }
        }
        if let moved = self.range(of: attachment) { textView.setSelectedRange(moved) }
    }

    /// The gap between top-level blocks nearest to `y`: before the first block whose middle is
    /// below it. Code blocks and quotes are one block each, so they're never split.
    private func dropGap(at y: CGFloat) -> (location: Int, y: CGFloat) {
        let origin = textView.textContainerOrigin
        var location = 0
        var previousKind: BlockKind?
        var lastBottom: CGFloat = origin.y
        while location < storage.length {
            let paragraph = paragraphRange(at: location)
            let kind = info(at: paragraph.location).kind
            defer {
                previousKind = kind
                location = NSMaxRange(paragraph)
            }
            guard let start = textRange(NSRange(location: paragraph.location, length: 0))?.location,
                  let fragment = layoutManager.textLayoutFragment(for: start)
            else { continue }
            let frame = fragment.layoutFragmentFrame.offsetBy(dx: 0, dy: origin.y)
            defer { lastBottom = frame.maxY }
            let insideGroup = previousKind == kind && (kind == .code || kind == .quote)
            if insideGroup { continue }
            let spacing = (storage.attribute(.paragraphStyle, at: paragraph.location, effectiveRange: nil) as? NSParagraphStyle)?.paragraphSpacingBefore ?? 0
            if frame.midY > y {
                return (paragraph.location, frame.minY + spacing / 2)
            }
        }
        return (storage.length, lastBottom)
    }

    /// Scrolls up to 12pt per update within 32pt of the visible edges (past the header/footer).
    private func autoscrollDuringDrag(at point: NSPoint) {
        guard let clip = textView.enclosingScrollView?.contentView else { return }
        let visible = clip.documentVisibleRect
        let zone: CGFloat = 32
        var delta: CGFloat = 0
        if point.y < visible.minY + verticalInset + zone { delta = -12 }
        else if point.y > visible.maxY - verticalInset - zone { delta = 12 }
        guard delta != 0 else { return }
        var origin = clip.bounds.origin
        origin.y = min(max(0, origin.y + delta), max(0, textView.frame.height - visible.height))
        clip.scroll(to: origin)
        textView.enclosingScrollView?.reflectScrolledClipView(clip)
    }
}
