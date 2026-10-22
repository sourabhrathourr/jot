import AppKit
import Carbon.HIToolbox

/// The system-wide "Show or Hide Jot" shortcut via Carbon's `RegisterEventHotKey`
/// (no Accessibility permission needed). A registered hot key reaches Jot before the
/// frontmost app sees the keystroke, so it wins over apps' own shortcuts (a browser's ⇧⌘N
/// doesn't open a window). It can be changed, paused while Settings records a new one, or
/// removed.
final class GlobalHotKey {
    private var reference: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let action: () -> Void
    private(set) var hotkey: Hotkey?

    /// Carbon's callback can't capture context, so the live instance is looked up here.
    nonisolated(unsafe) private static var current: GlobalHotKey?

    init(action: @escaping () -> Void) {
        self.action = action
        Self.current = self
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            MainActor.assumeIsolated { GlobalHotKey.current?.action() }
            return noErr
        }, 1, &spec, nil, &handler)
    }

    isolated deinit {
        unregister()
        if let handler { RemoveEventHandler(handler) }
    }

    /// Another owner of the same keys.
    enum Conflict: Error, Equatable {
        case raycast       // Raycast's own global hotkey
        case system        // an enabled macOS shortcut (Spotlight, Mission Control, screenshots…)
        case unavailable   // `RegisterEventHotKey` refused it

        var message: String {
            switch self {
            case .raycast: "Also Raycast's hotkey: change it there so only Jot answers"
            case .system: "Also a macOS shortcut: turn it off in System Settings → Keyboard"
            case .unavailable: "macOS didn't allow this shortcut"
            }
        }
    }

    /// Switches to `hotkey` (or removes the shortcut for `nil`). The user's choice wins: a
    /// clash with Raycast or a macOS shortcut is reported but the shortcut is still used.
    /// Only when macOS refuses it outright does the previous one stay.
    @discardableResult
    func register(_ hotkey: Hotkey?) -> Result<Conflict?, Conflict> {
        let previous = self.hotkey
        unregister()
        guard let hotkey else { return .success(nil) }
        guard attach(hotkey) else {
            _ = attach(previous)
            return .failure(.unavailable)
        }
        return .success(Self.knownConflict(for: hotkey))
    }

    /// Stops listening without forgetting the shortcut (while Settings records a new one).
    func pause() {
        let kept = hotkey
        unregister()
        hotkey = kept
    }

    func resume() {
        guard reference == nil, let hotkey else { return }
        _ = attach(hotkey)
    }

    private func attach(_ hotkey: Hotkey?) -> Bool {
        guard let hotkey else { return true }
        let id = EventHotKeyID(signature: OSType(0x4A4F_5421), id: 1) // "JOT!"
        var reference: EventHotKeyRef?
        let status = RegisterEventHotKey(hotkey.keyCode, Self.carbonFlags(hotkey.modifiers), id, GetApplicationEventTarget(), 0, &reference)
        guard status == noErr else { return false }
        self.reference = reference
        self.hotkey = hotkey
        return true
    }

    private func unregister() {
        if let reference { UnregisterEventHotKey(reference) }
        reference = nil
        hotkey = nil
    }

    /// Clashes `RegisterEventHotKey` can't see: Raycast's main hotkey and enabled macOS
    /// shortcuts (`CopySymbolicHotKeys`).
    static func knownConflict(for hotkey: Hotkey) -> Conflict? {
        if HyperKey.raycastGlobalHotkey() == hotkey { return .raycast }
        var symbolic: Unmanaged<CFArray>?
        guard CopySymbolicHotKeys(&symbolic) == noErr, let entries = symbolic?.takeRetainedValue() as? [[String: Any]] else { return nil }
        let flags = carbonFlags(hotkey.modifiers)
        for entry in entries {
            guard (entry[kHISymbolicHotKeyEnabled] as? Bool) == true,
                  let code = entry[kHISymbolicHotKeyCode] as? Int, code == Int(hotkey.keyCode),
                  let modifiers = entry[kHISymbolicHotKeyModifiers] as? Int else { continue }
            let relevant = UInt32(modifiers) & UInt32(cmdKey | optionKey | controlKey | shiftKey)
            if relevant == flags { return .system }
        }
        return nil
    }

    static func carbonFlags(_ flags: NSEvent.ModifierFlags) -> UInt32 {
        var result: UInt32 = 0
        if flags.contains(.command) { result |= UInt32(cmdKey) }
        if flags.contains(.option) { result |= UInt32(optionKey) }
        if flags.contains(.control) { result |= UInt32(controlKey) }
        if flags.contains(.shift) { result |= UInt32(shiftKey) }
        return result
    }
}
