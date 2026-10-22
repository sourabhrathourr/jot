import AppKit
import Carbon.HIToolbox

/// The global "Show or Hide Jot" shortcut: a key code and its modifiers. ⇧⌘N by default.
struct Hotkey: Equatable {
    var keyCode: UInt32
    var modifiers: NSEvent.ModifierFlags

    static let standard = Hotkey(keyCode: UInt32(kVK_ANSI_N), modifiers: [.command, .shift])
    static let relevantModifiers: NSEvent.ModifierFlags = [.command, .option, .control, .shift]
    /// "Hyper": every modifier at once, which Raycast's Hyper Key, Karabiner or the Hyperkey
    /// app send for a single key such as Caps Lock.
    static let hyper: NSEvent.ModifierFlags = [.command, .option, .control, .shift]

    init(keyCode: UInt32, modifiers: NSEvent.ModifierFlags) {
        self.keyCode = keyCode
        self.modifiers = modifiers.intersection(Self.relevantModifiers)
    }

    init?(event: NSEvent) {
        guard event.type == .keyDown else { return nil }
        self.init(keyCode: UInt32(event.keyCode), modifiers: event.modifierFlags)
    }

    /// Whether it uses every modifier of `hyper` (with or without Shift, see `HyperKey`).
    func isHyper(includingShift: Bool = HyperKey.includesShift) -> Bool {
        let required: NSEvent.ModifierFlags = includingShift ? Self.hyper : [.command, .option, .control]
        return modifiers.isSuperset(of: required)
    }

    /// A global shortcut needs ⌘, ⌥ or ⌃ (Shift alone would swallow typing), except on the
    /// function keys, which nothing types.
    var isValid: Bool {
        !modifiers.intersection([.command, .option, .control]).isEmpty || Self.functionKeys.contains(Int(keyCode))
    }

    /// The keycaps to draw, Raycast's way: Hyper becomes a single `✦` (plus `⇧` when the
    /// Hyper Key doesn't include Shift but Shift is held), then the key.
    var keycaps: [String] {
        let includesShift = HyperKey.includesShift
        guard isHyper(includingShift: includesShift) else { return Self.symbols(for: modifiers) + [Self.name(for: keyCode)] }
        let shift = !includesShift && modifiers.contains(.shift) ? ["⇧"] : []
        return shift + ["✦", Self.name(for: keyCode)]
    }

    /// One string for menus and tooltips, e.g. "⇧⌘N" or "✦N".
    var displayString: String { keycaps.joined() }

    /// ⌃⌥⇧⌘, in the order macOS menus use.
    static func symbols(for modifiers: NSEvent.ModifierFlags) -> [String] {
        var result: [String] = []
        if modifiers.contains(.control) { result.append("⌃") }
        if modifiers.contains(.option) { result.append("⌥") }
        if modifiers.contains(.shift) { result.append("⇧") }
        if modifiers.contains(.command) { result.append("⌘") }
        return result
    }

    // MARK: Key names

    private static let functionKeys: Set<Int> = [
        kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10,
        kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20,
    ]

    private static let specialNames: [Int: String] = [
        kVK_Return: "↩", kVK_Tab: "⇥", kVK_Space: "Space", kVK_Delete: "⌫", kVK_ForwardDelete: "⌦",
        kVK_Escape: "⎋", kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
        kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟", kVK_CapsLock: "⇪",
        kVK_ANSI_KeypadEnter: "⌤", kVK_Help: "Help",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
        kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
        kVK_F13: "F13", kVK_F14: "F14", kVK_F15: "F15", kVK_F16: "F16", kVK_F17: "F17",
        kVK_F18: "F18", kVK_F19: "F19", kVK_F20: "F20",
    ]

    /// The key's label on the current keyboard layout (so "Z" on a German layout is "Y").
    static func name(for keyCode: UInt32) -> String {
        if let special = specialNames[Int(keyCode)] { return special }
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            return "#\(keyCode)"
        }
        let data = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue() as Data
        var deadKeys: UInt32 = 0
        var length = 0
        var characters = [UniChar](repeating: 0, count: 4)
        let status = data.withUnsafeBytes { buffer -> OSStatus in
            guard let layout = buffer.bindMemory(to: UCKeyboardLayout.self).baseAddress else { return -1 }
            return UCKeyTranslate(layout, UInt16(keyCode), UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                                  OptionBits(kUCKeyTranslateNoDeadKeysBit), &deadKeys, characters.count, &length, &characters)
        }
        guard status == noErr, length > 0 else { return "#\(keyCode)" }
        return String(utf16CodeUnits: characters, count: length).uppercased()
    }

    // MARK: Storage

    private static let defaultsKey = "globalHotKey"

    /// The saved shortcut; `nil` when it was removed (no global shortcut at all).
    static var saved: Hotkey? {
        get {
            guard let stored = UserDefaults.standard.dictionary(forKey: defaultsKey) else { return .standard }
            guard let code = stored["keyCode"] as? Int, code >= 0, let raw = stored["modifiers"] as? Int else { return nil }
            return Hotkey(keyCode: UInt32(code), modifiers: NSEvent.ModifierFlags(rawValue: UInt(raw)))
        }
        set {
            let value: [String: Int] = newValue.map { ["keyCode": Int($0.keyCode), "modifiers": Int($0.modifiers.rawValue)] }
                ?? ["keyCode": -1, "modifiers": 0]
            UserDefaults.standard.set(value, forKey: defaultsKey)
        }
    }
}

/// Raycast's Hyper Key (Settings → Advanced → Hyper Key), read from Raycast's own preferences
/// (`com.raycast.macos.v1` → `raycast_hyperKey_state`: `enabled`, `keyCode`, `includeShiftKey`).
/// Whatever tool provides it, Hyper arrives as ⌃⌥⌘ (and ⇧), so a Jot shortcut recorded with it
/// works as long as that tool is running.
enum HyperKey {
    struct Raycast: Equatable {
        var keyCode: Int
        var includesShift: Bool

        /// "Caps Lock", "Right Control"… for the hint in Settings.
        var keyName: String {
            switch keyCode {
            case kVK_CapsLock: "Caps Lock"
            case kVK_RightControl: "Right Control"
            case kVK_RightOption: "Right Option"
            case kVK_RightCommand: "Right Command"
            case kVK_RightShift: "Right Shift"
            case kVK_Control: "Left Control"
            case kVK_Option: "Left Option"
            case kVK_Command: "Left Command"
            case kVK_Shift: "Left Shift"
            case kVK_Function: "Fn"
            default: Hotkey.name(for: UInt32(keyCode))
            }
        }
    }

    static func raycast(defaults: UserDefaults? = UserDefaults(suiteName: "com.raycast.macos.v1")) -> Raycast? {
        guard let state = defaults?.dictionary(forKey: "raycast_hyperKey_state"),
              (state["enabled"] as? Bool) == true || (state["enabled"] as? Int) == 1,
              let keyCode = state["keyCode"] as? Int else { return nil }
        let shift = (state["includeShiftKey"] as? Bool) ?? ((state["includeShiftKey"] as? Int).map { $0 != 0 } ?? true)
        return Raycast(keyCode: keyCode, includesShift: shift)
    }

    /// Whether Hyper includes Shift: Raycast's setting when it's on, otherwise the common
    /// ⌃⌥⇧⌘ of Karabiner and Hyperkey.
    static var includesShift: Bool { raycast()?.includesShift ?? true }

    static var modifiers: NSEvent.ModifierFlags {
        includesShift ? Hotkey.hyper : [.command, .option, .control]
    }

    /// Raycast's own global hotkey ("Shift-Control-Option-Command-15"), to report clashes.
    static func raycastGlobalHotkey(defaults: UserDefaults? = UserDefaults(suiteName: "com.raycast.macos.v1")) -> Hotkey? {
        guard let value = defaults?.string(forKey: "raycastGlobalHotkey") else { return nil }
        let parts = value.split(separator: "-")
        guard let last = parts.last, let code = UInt32(last) else { return nil }
        var modifiers: NSEvent.ModifierFlags = []
        for part in parts.dropLast() {
            switch part {
            case "Shift": modifiers.insert(.shift)
            case "Control": modifiers.insert(.control)
            case "Option": modifiers.insert(.option)
            case "Command": modifiers.insert(.command)
            default: break
            }
        }
        return Hotkey(keyCode: code, modifiers: modifiers)
    }
}
