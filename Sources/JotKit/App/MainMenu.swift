import AppKit

/// Every keyboard shortcut lives here (docs/DESIGN.md, "Behaviour and shortcuts").
/// Menus still route key equivalents for an LSUIElement app while it's active.
enum MainMenu {
    static func build(controller: NotesWindowController) -> NSMenu {
        let main = NSMenu()

        func submenu(_ title: String, _ items: [NSMenuItem]) {
            let menu = NSMenu(title: title)
            items.forEach(menu.addItem)
            let holder = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            holder.submenu = menu
            main.addItem(holder)
        }

        func item(_ title: String, _ action: Selector, _ key: String = "", _ modifiers: NSEvent.ModifierFlags = .command, target: AnyObject? = controller) -> NSMenuItem {
            let entry = NSMenuItem(title: title, action: action, keyEquivalent: key)
            entry.keyEquivalentModifierMask = modifiers
            entry.target = target
            return entry
        }

        let sep = { NSMenuItem.separator() }
        typealias C = NotesWindowController

        submenu("Jot", [
            item("About Jot", #selector(NSApplication.orderFrontStandardAboutPanel(_:)), target: nil),
            sep(),
            item("Hide Jot", #selector(NSApplication.hide(_:)), "h", target: nil),
            item("Quit Jot", #selector(NSApplication.terminate(_:)), "q", target: nil),
        ])

        submenu("Note", [
            item("New Note", #selector(C.newNote(_:)), "n"),
            item("Duplicate Note", #selector(C.duplicateNote(_:)), "d"),
            item("Browse Notes…", #selector(C.browseNotes(_:)), "p"),
            item("Action Panel…", #selector(C.showActionsMenu(_:)), "k"),
            item("Go Back", #selector(C.goBack(_:)), "["),
            item("Go Forward", #selector(C.goForward(_:)), "]"),
            sep(),
            item("Pin Note", #selector(C.togglePin(_:)), "p", [.command, .shift]),
            item("Copy Note As…", #selector(C.copyNoteAs(_:)), "c", [.command, .shift]),
            item("Copy Deeplink", #selector(C.copyDeeplink(_:)), "d", [.command, .shift]),
            item("Export…", #selector(C.exportNote(_:)), "e", [.command, .shift]),
            sep(),
            item("Show Recently Deleted Notes", #selector(C.showRecentlyDeleted(_:))),
            item("Delete Note", #selector(C.deleteNote(_:)), "x", .control),
            item("Delete All Notes", #selector(C.deleteAllNotes(_:)), "x", [.control, .shift]),
            item("Close Window", #selector(NSWindow.performClose(_:)), "w", target: nil),
        ])

        submenu("Edit", [
            item("Undo", Selector(("undo:")), "z", target: nil),
            item("Redo", Selector(("redo:")), "z", [.command, .shift], target: nil),
            sep(),
            item("Cut", #selector(NSText.cut(_:)), "x", target: nil),
            item("Copy", #selector(NSText.copy(_:)), "c", target: nil),
            item("Paste", #selector(NSText.paste(_:)), "v", target: nil),
            item("Paste and Match Style", #selector(NSTextView.pasteAsPlainText(_:)), "v", [.command, .option, .shift], target: nil),
            item("Select All", #selector(NSText.selectAll(_:)), "a", target: nil),
            sep(),
            item("Find…", #selector(C.showFind(_:)), "f"),
            item("Emoji & Symbols", #selector(NSApplication.orderFrontCharacterPalette(_:)), " ", [.command, .control], target: nil),
        ])

        submenu("Format", [
            item("Bold", #selector(C.toggleBold(_:)), "b"),
            item("Italic", #selector(C.toggleItalic(_:)), "i"),
            item("Underline", #selector(C.toggleUnderline(_:)), "u"),
            item("Strikethrough", #selector(C.toggleStrike(_:)), "s", [.command, .shift]),
            item("Code", #selector(C.toggleInlineCode(_:)), "e"),
            item("Link…", #selector(C.editLink(_:)), "l"),
            sep(),
            item("Body", #selector(C.setBody(_:)), "0", [.command, .option]),
            item("Heading 1", #selector(C.setHeading1(_:)), "1", [.command, .option]),
            item("Heading 2", #selector(C.setHeading2(_:)), "2", [.command, .option]),
            item("Heading 3", #selector(C.setHeading3(_:)), "3", [.command, .option]),
            sep(),
            item("Numbered List", #selector(C.toggleOrderedList(_:)), "7", [.command, .shift]),
            item("Bulleted List", #selector(C.toggleBulletList(_:)), "8", [.command, .shift]),
            item("Task List", #selector(C.toggleTaskList(_:)), "9", [.command, .shift]),
            item("Toggle Task", #selector(C.toggleTask(_:)), "\r"),
            sep(),
            item("Quote", #selector(C.toggleQuote(_:)), "b", [.command, .shift]),
            item("Code Block", #selector(C.toggleCodeBlock(_:)), "c", [.command, .option]),
            item("Add Image…", #selector(C.addImage(_:)), "i", [.command, .shift]),
            item("Divider", #selector(C.insertRule(_:)), "-", [.command, .shift]),
            sep(),
            item("Format…", #selector(C.showFormatMenu(_:)), ",", [.command, .shift]),
            item("Move List Item Up", #selector(C.moveListItemUp(_:)), String(UnicodeScalar(NSUpArrowFunctionKey)!), [.command, .control]),
            item("Move List Item Down", #selector(C.moveListItemDown(_:)), String(UnicodeScalar(NSDownArrowFunctionKey)!), [.command, .control]),
        ])

        submenu("View", [
            item("Show Format Bar", #selector(C.toggleFormatBar(_:)), ",", [.command, .option]),
            item("Auto-Size Window", #selector(C.toggleAutoSize(_:)), "/", [.command, .shift]),
            sep(),
            item("Zoom In", #selector(C.zoomIn(_:)), "="),
            item("Zoom Out", #selector(C.zoomOut(_:)), "-"),
            item("Actual Size", #selector(C.resetZoom(_:)), "0"),
        ])

        return main
    }
}
