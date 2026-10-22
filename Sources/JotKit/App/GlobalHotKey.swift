import AppKit
import Carbon.HIToolbox

/// A system-wide shortcut via Carbon's `RegisterEventHotKey` (no Accessibility permission needed).
final class GlobalHotKey {
    static let keyN = UInt32(kVK_ANSI_N)

    private var reference: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let action: () -> Void

    /// Carbon's callback can't capture context, so the live instance is looked up here.
    nonisolated(unsafe) private static var current: GlobalHotKey?

    init(keyCode: UInt32, modifiers: NSEvent.ModifierFlags, action: @escaping () -> Void) {
        self.action = action
        Self.current = self

        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            MainActor.assumeIsolated { GlobalHotKey.current?.action() }
            return noErr
        }, 1, &spec, nil, &handler)

        let id = EventHotKeyID(signature: OSType(0x4A4F_5421), id: 1) // "JOT!"
        let status = RegisterEventHotKey(keyCode, Self.carbonFlags(modifiers), id, GetApplicationEventTarget(), 0, &reference)
        isRegistered = status == noErr
        if !isRegistered {
            // eventHotKeyExistsErr (-9878): another app already owns this combination.
            FileHandle.standardError.write(Data("Jot: couldn't register the global hotkey (OSStatus \(status))\n".utf8))
        }
    }

    private(set) var isRegistered = false

    isolated deinit {
        if let reference { UnregisterEventHotKey(reference) }
        if let handler { RemoveEventHandler(handler) }
    }

    private static func carbonFlags(_ flags: NSEvent.ModifierFlags) -> UInt32 {
        var result: UInt32 = 0
        if flags.contains(.command) { result |= UInt32(cmdKey) }
        if flags.contains(.option) { result |= UInt32(optionKey) }
        if flags.contains(.control) { result |= UInt32(controlKey) }
        if flags.contains(.shift) { result |= UInt32(shiftKey) }
        return result
    }
}
