import AppKit

public enum JotApp {
    public static func run() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: NotesWindowController?
    private var statusItem: NSStatusItem?
    private var hotKey: GlobalHotKey?
    private var settings: SettingsWindowController?
    private let updater = JotUpdater()
    private var openItem: NSMenuItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // A menu-bar utility like Raycast (LSUIElement); `swift run` needs this set explicitly.
        NSApp.setActivationPolicy(.accessory)
        Fonts.registerBundledFonts()

        let repository: NotesRepository
        do {
            repository = try NotesRepository(path: try NotesRepository.defaultPath())
        } catch {
            let alert = NSAlert()
            alert.messageText = "Jot couldn't open its database"
            alert.informativeText = "\(error)"
            alert.runModal()
            NSApp.terminate(nil)
            return
        }

        let controller = NotesWindowController(repository: repository)
        self.controller = controller
        NSApp.mainMenu = MainMenu.build(controller: controller)
        let hotKey = GlobalHotKey { [weak controller] in controller?.toggle() }
        if case .failure(let conflict) = hotKey.register(Hotkey.saved) {
            FileHandle.standardError.write(Data("Jot: couldn't register the global shortcut (\(conflict.message))\n".utf8))
        }
        self.hotKey = hotKey
        installSettings(controller: controller)
        installStatusItem()
        controller.show()
        if ProcessInfo.processInfo.environment["JOT_OPEN_SETTINGS"] != nil { settings?.show() }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        controller?.show()
        return false
    }

    /// `jot://notes/<id>` from "Copy Deeplink".
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where url.scheme == "jot" && url.host == "notes" {
            let id = url.lastPathComponent
            controller?.open(id: id)
            controller?.show()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller?.flush()
    }

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "note.text", accessibilityDescription: "Jot")
        let menu = NSMenu()
        let open = NSMenuItem(title: "Open Notes", action: #selector(openNotes), keyEquivalent: "")
        open.target = self
        menu.addItem(open)
        openItem = open
        updateOpenItemShortcut()
        let new = NSMenuItem(title: "New Note", action: #selector(NotesWindowController.newNote(_:)), keyEquivalent: "")
        new.target = controller
        menu.addItem(new)
        menu.addItem(.separator())
        let updatesItem = NSMenuItem(title: "Check for Updates…", action: #selector(checkForUpdates(_:)), keyEquivalent: "")
        updatesItem.target = self
        menu.addItem(updatesItem)
        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        menu.addItem(NSMenuItem(title: "Quit Jot", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        item.menu = menu
        statusItem = item
    }

    @objc private func openNotes() { controller?.show() }

    @objc private func showSettings() { settings?.show() }

    /// From the Jot menu (through the responder chain) and the menu bar icon.
    @objc func checkForUpdates(_ sender: Any?) { updater.checkForUpdates() }

    @objc func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        menuItem.action == #selector(checkForUpdates(_:)) ? updater.canCheckForUpdates : true
    }

    /// Settings changes the global shortcut through the one `GlobalHotKey`.
    private func installSettings(controller: NotesWindowController) {
        let model = SettingsModel(hotkey: hotKey?.hotkey)
        model.apply = { [weak self] hotkey in
            guard let self, let hotKey else { return .success(nil) }
            let result = hotKey.register(hotkey)
            if case .success = result { updateOpenItemShortcut() }
            return result
        }
        model.onRecordingChange = { [weak self] recording in
            if recording { self?.hotKey?.pause() } else { self?.hotKey?.resume() }
        }
        settings = SettingsWindowController(model: model)
        controller.onShowSettings = { [weak self] in self?.settings?.show() }
    }

    /// The status menu shows the current global shortcut next to "Open Notes".
    private func updateOpenItemShortcut() {
        guard let openItem else { return }
        let hotkey = hotKey?.hotkey
        openItem.keyEquivalent = hotkey.map { Hotkey.name(for: $0.keyCode).lowercased() } ?? ""
        openItem.keyEquivalentModifierMask = hotkey?.modifiers ?? []
    }
}

/// First-run note, in the spirit of Raycast's "Welcome to Raycast Notes".
enum WelcomeNote {
    static var blocks: [Block] {
        [
            Block(kind: .heading1, runs: [Run(text: "Welcome to Jot")]),
            Block.paragraph("A small native scratchpad for ideas, meeting notes, and things you want to jot down quickly."),
            Block(kind: .rule),
            Block(kind: .heading2, runs: [Run(text: "📑 Browsing Notes")]),
            Block(kind: .paragraph, runs: [
                Run(text: "Find your notes with "), Run(text: "⌘", marks: .code), Run(text: " "), Run(text: "P", marks: .code),
                Run(text: " or the panel button in the title bar."),
            ]),
            Block(kind: .heading2, runs: [Run(text: "✍️ Formatting")]),
            Block(kind: .paragraph, runs: [
                Run(text: "Type Markdown as you go: "), Run(text: "#", marks: .code), Run(text: " for headings, "),
                Run(text: "-", marks: .code), Run(text: " for lists, "), Run(text: "[]", marks: .code),
                Run(text: " for tasks, "), Run(text: "bold", marks: .bold), Run(text: ", "),
                Run(text: "italic", marks: .italic), Run(text: " and "), Run(text: "code", marks: .code), Run(text: "."),
            ]),
            Block(kind: .task, checked: true, runs: [Run(text: "Open Jot with ⇧⌘N from anywhere")]),
            Block(kind: .task, runs: [Run(text: "Write your first note")]),
            Block(kind: .heading2, runs: [Run(text: "📏 Window Resizing")]),
            Block.paragraph("The window grows with your note. Resize it yourself to pin its size; turn auto-sizing back on from the View menu."),
        ]
    }

    /// Every block type, for visual checks (`JOT_DEMO=1`).
    static var showcase: [Block] {
        [
            Block(kind: .heading1, runs: [Run(text: "Showcase")]),
            Block(kind: .paragraph, runs: [
                Run(text: "Plain, "), Run(text: "bold", marks: .bold), Run(text: ", "), Run(text: "italic", marks: .italic),
                Run(text: ", "), Run(text: "underline", marks: .underline), Run(text: ", "), Run(text: "strike", marks: .strike),
                Run(text: ", "), Run(text: "inline code", marks: .code), Run(text: " and a "), Run(text: "link", link: "https://raycast.com"), Run(text: "."),
            ]),
            Block(kind: .heading2, runs: [Run(text: "Lists")]),
            Block(kind: .bullet, runs: [Run(text: "First bullet")]),
            Block(kind: .bullet, indent: 1, runs: [Run(text: "Nested bullet")]),
            Block(kind: .bullet, indent: 2, runs: [Run(text: "Deeper bullet")]),
            Block(kind: .ordered, runs: [Run(text: "One")]),
            Block(kind: .ordered, runs: [Run(text: "Two")]),
            Block(kind: .ordered, indent: 1, runs: [Run(text: "Two point one")]),
            Block(kind: .ordered, runs: [Run(text: "Three")]),
            Block(kind: .task, checked: true, runs: [Run(text: "Done task with "), Run(text: "code", marks: .code)]),
            Block(kind: .task, runs: [Run(text: "Open task")]),
            Block(kind: .heading3, runs: [Run(text: "Quote & code")]),
            Block(kind: .quote, runs: [Run(text: "Simplicity is prerequisite for reliability.")]),
            Block(kind: .quote, runs: [Run(text: "— Edsger W. Dijkstra")]),
            Block(kind: .code, runs: [Run(text: "func greet(_ name: String) -> String {")]),
            Block(kind: .code, runs: [Run(text: "    \"Hello, \\(name)\"")]),
            Block(kind: .code, runs: [Run(text: "}")]),
            Block(kind: .rule),
            Block.paragraph("The end."),
        ]
    }
}
