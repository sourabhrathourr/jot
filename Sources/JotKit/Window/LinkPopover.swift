import AppKit

/// ⌘L: "Enter a link…" popover anchored to the selection.
final class LinkPopover: NSObject, NSTextFieldDelegate {
    private let popover = NSPopover()
    private let field = NSTextField()
    private var onCommit: (String?) -> Void = { _ in }

    override init() {
        super.init()
        field.placeholderString = "Enter a link…"
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = Fonts.ui(size: 13)
        field.delegate = self
        field.translatesAutoresizingMaskIntoConstraints = false
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 280, height: 36))
        container.addSubview(field)
        NSLayoutConstraint.activate([
            field.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            field.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
            field.centerYAnchor.constraint(equalTo: container.centerYAnchor),
        ])
        let controller = NSViewController()
        controller.view = container
        popover.contentViewController = controller
        popover.behavior = .transient
    }

    func show(relativeTo rect: NSRect, of view: NSView, href: String?, onCommit: @escaping (String?) -> Void) {
        self.onCommit = onCommit
        field.stringValue = href ?? ""
        popover.show(relativeTo: rect, of: view, preferredEdge: .maxY)
        popover.contentViewController?.view.window?.makeFirstResponder(field)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.insertNewline(_:)):
            onCommit(field.stringValue)
            popover.close()
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            popover.close()
            return true
        default:
            return false
        }
    }
}
