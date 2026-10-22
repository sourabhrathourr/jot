import AppKit
import Quartz

extension NSPasteboard.PasteboardType {
    /// Tiptap-shaped JSON of the copied blocks, so formatting survives copy/paste.
    static let jotBlocks = NSPasteboard.PasteboardType("com.sourabh.jot.blocks")
}

/// The TextKit 2 text view. Behaviour lives in `NoteEditor`; this class only
/// forwards the hooks NSTextView doesn't expose through its delegate.
final class NoteTextView: NSTextView {
    weak var editor: NoteEditor?

    /// TextKit ignores `paragraphSpacingBefore` on the first paragraph, but CSS keeps the
    /// first block's top margin inside the editor padding, so it's applied here instead.
    var firstBlockSpacing: CGFloat = 0 {
        didSet {
            guard firstBlockSpacing != oldValue else { return }
            invalidateTextContainerOrigin()
            needsDisplay = true
        }
    }

    override var textContainerOrigin: NSPoint {
        var origin = super.textContainerOrigin
        origin.y += firstBlockSpacing
        return origin
    }

    /// The text always ends with a newline that anchors the last block; the empty line after
    /// it isn't a real paragraph. Clamp every selection change (including the ones made while
    /// the mouse is still down, which the delegate never sees) so the caret can't land there.
    override func setSelectedRanges(_ ranges: [NSValue], affinity: NSSelectionAffinity, stillSelecting: Bool) {
        var ranges = ranges
        let length = textStorage?.length ?? 0
        if length > 0, ranges.count == 1 {
            let range = ranges[0].rangeValue
            if range.length == 0, range.location >= length {
                ranges = [NSValue(range: NSRange(location: length - 1, length: 0))]
            }
        }
        if ProcessInfo.processInfo.environment["JOT_DEBUG_CARET"] != nil {
            let r = ranges.first?.rangeValue ?? NSRange()
            FileHandle.standardError.write(Data(String(format: "%.3f setSelected loc=%d len=%d stillSelecting=%d textLength=%d\n", Date().timeIntervalSince1970.truncatingRemainder(dividingBy: 1000), r.location, r.length, stillSelecting ? 1 : 0, length).utf8))
        }
        super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: stillSelecting)
    }

    override func insertText(_ string: Any, replacementRange: NSRange) {
        let typed = (string as? String) ?? (string as? NSAttributedString)?.string ?? ""
        if editor?.handleBeforeInsert(typed) == true { return }
        super.insertText(string, replacementRange: replacementRange)
        editor?.handleAfterInsert(typed)
    }

    /// The slash menu takes its keys first while it's open (the editor keeps focus).
    override func keyDown(with event: NSEvent) {
        if editor?.slashMenu.handleKey(event) == true { return }
        super.keyDown(with: event)
    }

    /// ⌘1–9, ⌘0 and ⌘↑↓ reach the slash menu before the main menu's shortcuts.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.type == .keyDown, window?.firstResponder === self, editor?.slashMenu.handleKey(event) == true { return true }
        return super.performKeyEquivalent(with: event)
    }

    override func mouseDown(with event: NSEvent) {
        if editor?.handleMouseDown(event) == true { return }
        super.mouseDown(with: event)
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        if editor?.isOverInteractiveMarker(event) == true { NSCursor.pointingHand.set() }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        editor?.appearanceDidChange()
    }

    // MARK: Pasteboard

    override var writablePasteboardTypes: [NSPasteboard.PasteboardType] { [.jotBlocks, .string] }

    override func writeSelection(to pboard: NSPasteboard, type: NSPasteboard.PasteboardType) -> Bool {
        guard let editor else { return super.writeSelection(to: pboard, type: type) }
        switch type {
        case .jotBlocks: return pboard.setString(editor.selectionJSON(), forType: .jotBlocks)
        case .string: return pboard.setString(editor.selectionPlainText(), forType: .string)
        default: return super.writeSelection(to: pboard, type: type)
        }
    }

    /// AppKit only enables Paste when the clipboard holds one of these, so the image types
    /// must be listed for a screenshot (PNG/TIFF only) to be pasteable at all.
    override var readablePasteboardTypes: [NSPasteboard.PasteboardType] {
        [.jotBlocks, .fileURL] + NoteEditor.pastedImageTypes + [.string]
    }

    /// Every read (Paste, Paste and Match Style, Services) goes through the editor: inside a
    /// code block only text; Jot's own blocks keep their formatting; images become image blocks;
    /// other text is read as Markdown (Raycast's `clipboardTextParser`).
    override func readSelection(from pboard: NSPasteboard, type: NSPasteboard.PasteboardType) -> Bool {
        guard let editor else { return super.readSelection(from: pboard, type: type) }
        return editor.paste(from: pboard)
    }

    // MARK: Images

    /// ⌘V goes through the editor so screenshots and image files become image blocks.
    override func paste(_ sender: Any?) {
        if editor?.paste(from: .general) == true { return }
        super.paste(sender)
    }

    /// With an image selected, ⌘C copies the image itself (Raycast's "Copy Image").
    override func copy(_ sender: Any?) {
        if let editor, editor.selectedImage != nil {
            editor.copySelectedImage()
            return
        }
        super.copy(sender)
    }

    override func cut(_ sender: Any?) {
        if let editor, let image = editor.selectedImage, let range = editor.range(of: image) {
            editor.copySelectedImage()
            editor.deleteImageBlock((string as NSString).paragraphRange(for: range))
            return
        }
        super.cut(sender)
    }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        editor?.imageDragUpdated(sender) ?? super.draggingEntered(sender)
    }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        editor?.imageDragUpdated(sender) ?? super.draggingUpdated(sender)
    }

    override func draggingExited(_ sender: (any NSDraggingInfo)?) {
        hideDropIndicator()
        super.draggingExited(sender)
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        if editor?.performImageDrop(sender) == true { return true }
        return super.performDragOperation(sender)
    }

    override func concludeDragOperation(_ sender: (any NSDraggingInfo)?) {
        hideDropIndicator()
        super.concludeDragOperation(sender)
    }

    /// Raycast's drop indicator: a 2pt accent bar between blocks.
    private lazy var dropIndicator: NSView = {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = Theme.accent.cgColor
        view.layer?.cornerRadius = 1
        view.isHidden = true
        return view
    }()

    func showDropIndicator(at y: CGFloat) {
        if dropIndicator.superview == nil { addSubview(dropIndicator) }
        let x = textContainerOrigin.x
        let width = textContainer?.size.width ?? bounds.width - x * 2
        dropIndicator.frame = CGRect(x: x, y: (y - 1).rounded(), width: width, height: 2)
        dropIndicator.isHidden = false
    }

    func hideDropIndicator() {
        dropIndicator.isHidden = true
    }

    /// Right-clicking an image selects it and offers Quick Look, Copy Image and Save As….
    override func menu(for event: NSEvent) -> NSMenu? {
        if let editor, let image = editor.image(at: convert(event.locationInWindow, from: nil)) {
            editor.select(image)
            return editor.imageMenu()
        }
        return super.menu(for: event)
    }

    // MARK: Quick Look

    func toggleQuickLook() {
        guard let panel = QLPreviewPanel.shared() else { return }
        if QLPreviewPanel.sharedPreviewPanelExists(), panel.isVisible {
            panel.orderOut(nil)
        } else {
            panel.makeKeyAndOrderFront(nil)
        }
    }

    // QLPreviewPanel asks the responder chain on the main thread.
    nonisolated override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool {
        MainActor.assumeIsolated { editor?.selectedImageURL != nil }
    }

    nonisolated override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        MainActor.assumeIsolated {
            panel.dataSource = self
            panel.delegate = self
            // Above the notes window, which floats at the modal-panel level.
            if let window { panel.level = NSWindow.Level(rawValue: window.level.rawValue + 1) }
            panel.reloadData()
        }
    }

    nonisolated override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        MainActor.assumeIsolated {
            panel.dataSource = nil
            panel.delegate = nil
        }
    }

    override func selectAll(_ sender: Any?) {
        if editor?.handleSelectAll() == true { return }
        super.selectAll(sender)
    }
}

extension NoteTextView: @preconcurrency QLPreviewPanelDataSource, @preconcurrency QLPreviewPanelDelegate {
    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        editor?.selectedImageURL == nil ? 0 : 1
    }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
        editor?.selectedImageURL as NSURL?
    }

    /// Quick Look zooms out of the image on screen.
    func previewPanel(_ panel: QLPreviewPanel!, sourceFrameOnScreenFor item: (any QLPreviewItem)!) -> NSRect {
        editor?.selectedImageScreenFrame ?? .zero
    }

    func previewPanel(_ panel: QLPreviewPanel!, transitionImageFor item: (any QLPreviewItem)!, contentRect: UnsafeMutablePointer<NSRect>!) -> Any! {
        guard let editor, let image = editor.selectedImage else { return nil }
        return editor.snapshot(of: image)
    }

    /// Space closes the preview again, like Finder.
    func previewPanel(_ panel: QLPreviewPanel!, handle event: NSEvent!) -> Bool {
        if event.type == .keyDown, event.charactersIgnoringModifiers == " " {
            panel.orderOut(nil)
            return true
        }
        return false
    }
}
