import AppKit
import SwiftUI

/// The slash menu's popover (`pn`): the command menu's list without a search field, 280pt
/// wide and at most 280pt tall, 8pt under the "/query" text and 16pt to its left so the
/// icons line up with the "/", flipping above when there's no room below. `pn` passes no
/// animation, so it simply appears and disappears. It never takes key focus; the editor
/// forwards its keys.
final class SlashMenuPanel: MenuPanel {
    let model: MenuModel
    var onOutsideClick: () -> Void = {}
    private var clickMonitor: Any?
    private var resignObserver: NSObjectProtocol?
    private var placedAbove = false

    static let width: CGFloat = 280
    static let maxHeight: CGFloat = 280
    static let offset: CGFloat = 8
    static let alignOffset: CGFloat = -16
    /// The web fallback's viewport margins: 16 for flipping, 8 for the sides.
    static let flipMargin: CGFloat = 16
    static let sideMargin: CGFloat = 8

    init(model: MenuModel) {
        self.model = model
        super.init(cornerRadius: 18, size: NSSize(width: Self.width, height: 200), nonactivating: true)
        let list = NSHostingView(rootView: MenuList(model: model))
        // The panel is titled (for its frame), but the list shouldn't inset for a title bar.
        list.safeAreaRegions = []
        glass.contentView = list
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    private var height: CGFloat { min(Self.maxHeight, model.contentHeight) }

    /// Shows the menu for `anchor`, the "/query" rect in screen coordinates.
    func show(anchor: NSRect, in parent: NSWindow) {
        let height = self.height
        let screen = (parent.screen ?? NSScreen.main)?.visibleFrame ?? parent.frame
        var origin = NSPoint(x: anchor.minX + Self.alignOffset, y: anchor.minY - Self.offset - height)
        placedAbove = origin.y < screen.minY + Self.flipMargin && anchor.maxY + Self.offset + height <= screen.maxY - Self.flipMargin
        if placedAbove { origin.y = anchor.maxY + Self.offset }
        origin.x = min(max(origin.x, screen.minX + Self.sideMargin), screen.maxX - Self.width - Self.sideMargin)
        setFrame(NSRect(origin: origin, size: NSSize(width: Self.width, height: height)), display: true)
        guard !isVisible else { return }
        model.pointer = NSEvent.mouseLocation
        parent.addChildWindow(self, ordered: .above)
        orderFront(nil)
        watchOutside(parent)
    }

    /// The rows changed: keep the edge next to the text where it is.
    func fitHeight() {
        var frame = self.frame
        if !placedAbove { frame.origin.y += frame.height - height }
        frame.size.height = height
        setFrame(frame, display: true)
    }

    override func close() {
        guard isVisible else { return }
        stopWatching()
        parent?.removeChildWindow(self)
        orderOut(nil)
    }

    /// `dismissOnOutsideClick` (the click is swallowed in the notes window), and the notes
    /// window losing focus.
    private func watchOutside(_ parent: NSWindow) {
        stopWatching()
        clickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self, event.window !== self else { return event }
            onOutsideClick()
            return event.window === parent ? nil : event
        }
        resignObserver = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: parent, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.onOutsideClick() }
        }
    }

    private func stopWatching() {
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        clickMonitor = nil
        resignObserver = nil
    }
}
