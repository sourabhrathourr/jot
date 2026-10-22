import AppKit

/// Raycast's `NotesWindow : WebViewPanel : NSPanel`, minus the web view:
/// a floating, transparent-titled panel whose content is Liquid Glass.
final class NotesPanel: NSPanel {
    init() {
        super.init(
            contentRect: NSRect(origin: .zero, size: Layout.defaultSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        title = "Notes"
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        titlebarSeparatorStyle = .none
        // An empty unified toolbar gives the 52pt title bar Raycast uses, with the
        // traffic lights vertically centred in it.
        toolbar = NSToolbar(identifier: "jot.toolbar")
        toolbarStyle = .unified
        isMovableByWindowBackground = true
        isFloatingPanel = true
        // Raycast's NotesWindow sits at the modal-panel level (CGWindowLevel 8); matching it
        // keeps Jot above ordinary floating windows and lets the focused of the two be on top.
        level = .modalPanel
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isReleasedWhenClosed = false
        minSize = Layout.minSize
        collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        animationBehavior = .utilityWindow
        ScreenSharing.apply(to: self)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    /// Double-click on the header (Raycast: re-enable auto-size, else toggle zoom).
    var onHeaderDoubleClick: (() -> Void)?

    /// Raycast's drag region: a left mouse-down on the header that isn't on a control
    /// hands the drag to the window server (`performWindowDrag`), so the window tracks
    /// the cursor exactly. Handled here, before the toolbar or content views see it.
    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown, isInHeaderDragRegion(event) {
            if event.clickCount == 2 {
                onHeaderDoubleClick?()
            } else {
                performDrag(with: event)
            }
            return
        }
        super.sendEvent(event)
    }

    private func isInHeaderDragRegion(_ event: NSEvent) -> Bool {
        guard let content = contentView else { return false }
        let point = event.locationInWindow
        let local = content.convert(point, from: nil)
        let fromTop = content.isFlipped ? local.y : content.bounds.height - local.y
        guard fromTop >= 0, fromTop <= Layout.headerHeight else { return false }

        // Leave the window's resize edges and corners to AppKit: the top border and the
        // upper part of the side borders run through the header.
        let edge: CGFloat = 6
        let corner: CGFloat = 16
        let width = content.bounds.width
        if fromTop < edge || local.x < edge || local.x > width - edge { return false }
        if fromTop < corner && (local.x < corner || local.x > width - corner) { return false }

        // Traffic lights keep their own behaviour.
        for type in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            if let button = standardWindowButton(type), button.alphaValue > 0,
               button.convert(button.bounds, to: nil).insetBy(dx: -2, dy: -2).contains(point) {
                return false
            }
        }
        // Buttons and fields are interactive, everything else in the header drags.
        var view = content.hitTest(content.superview?.convert(point, from: nil) ?? point)
        while let current = view {
            if current is NSControl && !(current is NSTextField && !(current as! NSTextField).isEditable) { return false }
            if current is NSTextView { return false }
            view = current.superview
        }
        return true
    }

    /// Escape hides the panel like Raycast does.
    override func cancelOperation(_ sender: Any?) {
        orderOut(sender)
    }
}

/// A view that lets the window be dragged from it (header background).
class DragView: NSView {
    override var mouseDownCanMoveWindow: Bool { true }
}

/// A label that ignores the mouse so the header behind it stays draggable.
final class PassthroughLabel: NSTextField {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// Tracks whether the pointer is inside the window (Raycast's `[window-hovered]`).
final class HoverView: NSView {
    var onHoverChange: ((Bool) -> Void)?
    private var area: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let area { removeTrackingArea(area) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area)
        self.area = area
    }

    override func mouseEntered(with event: NSEvent) { onHoverChange?(true) }
    override func mouseExited(with event: NSEvent) { onHoverChange?(false) }
}
