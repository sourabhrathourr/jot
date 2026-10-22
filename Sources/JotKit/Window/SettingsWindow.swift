import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Settings (⌘,): the "Show or Hide Jot" shortcut, with Raycast's Hyper Key when it's on,
/// and Hide from Screen Sharing.
@Observable
final class SettingsModel {
    var hotkey: Hotkey?
    var isRecording = false {
        didSet { if isRecording != oldValue { onRecordingChange(isRecording) } }
    }
    /// Modifiers held while recording, shown before the key arrives.
    var heldModifiers: NSEvent.ModifierFlags = []
    var message: String?
    /// The message is a warning (the shortcut was still saved), not an error.
    var messageIsWarning = false
    var raycastHyper: HyperKey.Raycast?
    var hidesFromScreenSharing = ScreenSharing.isHidden {
        didSet { if ScreenSharing.isHidden != hidesFromScreenSharing { ScreenSharing.isHidden = hidesFromScreenSharing } }
    }

    /// Registers a shortcut (nil removes it); the app delegate owns the `GlobalHotKey`.
    @ObservationIgnored var apply: (Hotkey?) -> Result<GlobalHotKey.Conflict?, GlobalHotKey.Conflict> = { _ in .success(nil) }
    /// Pauses the current shortcut while recording, so pressing it records instead of hiding Jot.
    @ObservationIgnored var onRecordingChange: (Bool) -> Void = { _ in }

    init(hotkey: Hotkey?) {
        self.hotkey = hotkey
        raycastHyper = HyperKey.raycast()
    }

    func refresh() {
        raycastHyper = HyperKey.raycast()
        hidesFromScreenSharing = ScreenSharing.isHidden
    }

    func toggleRecording() {
        isRecording.toggle()
        heldModifiers = []
        message = nil
    }

    /// Raycast's recorder keys: Esc cancels, ⌫ removes the shortcut, anything else with
    /// ⌘, ⌥ or ⌃ (or a function key) becomes the new shortcut. Returns whether it was used.
    func handle(_ event: NSEvent) -> Bool {
        guard isRecording else { return false }
        if event.type == .flagsChanged {
            heldModifiers = event.modifierFlags.intersection(Hotkey.relevantModifiers)
            return true
        }
        guard event.type == .keyDown else { return false }
        let modifiers = event.modifierFlags.intersection(Hotkey.relevantModifiers)
        if modifiers.isEmpty, event.keyCode == UInt16(kVK_Escape) {
            isRecording = false
            heldModifiers = []
            return true
        }
        if modifiers.isEmpty, event.keyCode == UInt16(kVK_Delete) || event.keyCode == UInt16(kVK_ForwardDelete) {
            save(nil)
            return true
        }
        guard let candidate = Hotkey(event: event) else { return false }
        guard candidate.isValid else {
            message = "Add ⌘, ⌥ or ⌃ to the key"
            messageIsWarning = false
            return true
        }
        save(candidate)
        return true
    }

    func reset() { save(.standard) }

    /// Raycast's Hyper Key with N, the default's letter.
    func useHyper() { save(Hotkey(keyCode: UInt32(kVK_ANSI_N), modifiers: HyperKey.modifiers)) }

    private func save(_ candidate: Hotkey?) {
        switch apply(candidate) {
        case .success(let warning):
            hotkey = candidate
            Hotkey.saved = candidate
            message = warning?.message
            messageIsWarning = warning != nil
            isRecording = false
            heldModifiers = []
        case .failure(let conflict):
            message = conflict.message
            messageIsWarning = false
        }
    }
}

/// A small window in Jot's material, above the notes panel.
final class SettingsWindowController: NSObject, NSWindowDelegate {
    let model: SettingsModel
    private var window: SettingsWindow?
    private var monitor: Any?

    init(model: SettingsModel) {
        self.model = model
        super.init()
        model.onRecordingChange = { [weak self, previous = model.onRecordingChange] recording in
            previous(recording)
            self?.setMonitoring(recording)
        }
    }

    func show() {
        model.refresh()
        let window = self.window ?? makeWindow()
        self.window = window
        if !window.isVisible { window.center() }
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> SettingsWindow {
        let window = SettingsWindow(model: model)
        window.delegate = self
        return window
    }

    /// While recording, key events go to the recorder instead of the menus and other views.
    private func setMonitoring(_ recording: Bool) {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        guard recording else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged, .leftMouseDown]) { [weak self] event in
            guard let self else { return event }
            if event.type == .leftMouseDown {
                // Clicking anywhere but the field stops recording.
                if event.window !== window || !(window?.isRecorderHit(event) ?? false) { model.isRecording = false }
                return event
            }
            return model.handle(event) ? nil : event
        }
    }

    func windowDidResignKey(_ notification: Notification) {
        model.isRecording = false
    }
}

final class SettingsWindow: NSWindow, CornerRadiusProviding {
    let customCornerRadius: CGFloat = 16
    private let recorderFrame = RecorderFrame()

    init(model: SettingsModel) {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 460, height: 300), styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        title = "Jot Settings"
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = true
        isReleasedWhenClosed = false
        // The notes panel sits at the modal-panel level; Settings opens above it.
        level = .modalPanel
        isOpaque = false
        backgroundColor = .clear
        let backdrop = WindowBackdropView(cornerRadius: customCornerRadius)
        let host = NSHostingView(rootView: SettingsView(model: model, recorderFrame: recorderFrame))
        // The title sits in the title bar row itself, so no safe-area inset for it.
        host.safeAreaRegions = []
        backdrop.contentView = host
        contentView = backdrop
        setContentSize(host.fittingSize)
        GlassRecipe.apply(to: self)
        WindowCornerRadius.install(on: self)
        ScreenSharing.apply(to: self)
    }

    func isRecorderHit(_ event: NSEvent) -> Bool {
        guard let content = contentView else { return false }
        let point = content.convert(event.locationInWindow, from: nil)
        let flipped = NSPoint(x: point.x, y: content.bounds.height - point.y)
        return recorderFrame.rect.contains(flipped)
    }

    /// Escape closes Settings, unless it's recording a shortcut (then it cancels that).
    override func cancelOperation(_ sender: Any?) { close() }
}

/// Where the recorder sits, so a click on it isn't treated as a click elsewhere.
final class RecorderFrame {
    var rect: CGRect = .zero
}

// MARK: - SwiftUI

private struct SettingsView: View {
    @Bindable var model: SettingsModel
    let recorderFrame: RecorderFrame

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Settings")
                .font(uiFont(13, .medium))
                .foregroundStyle(nsColor(Theme.textSecondary))
                .frame(maxWidth: .infinity)
                .frame(height: 32)
                .padding(.bottom, 16)

            row(title: "Show or Hide Jot", detail: "Opens Jot from any app.") {
                HotkeyField(model: model, recorderFrame: recorderFrame)
            }
            Text(model.message ?? hint)
                .font(uiFont(11))
                .foregroundStyle(nsColor(model.message == nil ? Theme.textTertiary : model.messageIsWarning ? Theme.yellow : Theme.red))
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.top, 6)

            HyperHint(model: model)
                .padding(.top, 14)

            Rectangle().fill(nsColor(Theme.separator)).frame(height: 0.5).padding(.vertical, 18)

            row(title: "Hide from Screen Sharing", detail: "Keeps Jot out of screen shares, recordings and screenshots.") {
                Toggle("", isOn: $model.hidesFromScreenSharing)
                    .toggleStyle(.switch)
                    .tint(nsColor(Theme.accent))
                    .labelsHidden()
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
        .frame(width: 460)
    }

    private var hint: String {
        model.isRecording ? "Press keys, ⎋ to cancel, ⌫ to remove" : model.hotkey == nil ? "No shortcut: open Jot from the menu bar" : " "
    }

    private func row<Control: View>(title: String, detail: String, @ViewBuilder control: () -> Control) -> some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(uiFont(13, .medium)).foregroundStyle(nsColor(Theme.textPrimary))
                Text(detail).font(uiFont(12)).foregroundStyle(nsColor(Theme.textSecondary))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            control()
        }
    }
}

/// Click to record; shows the shortcut as keycaps, or the modifiers held while recording.
private struct HotkeyField: View {
    @Bindable var model: SettingsModel
    let recorderFrame: RecorderFrame
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 6) {
            Button { model.toggleRecording() } label: {
                HStack(spacing: 4) {
                    if model.isRecording {
                        let held = Hotkey.symbols(for: model.heldModifiers)
                        if held.isEmpty {
                            Text("Recording…").font(uiFont(12)).foregroundStyle(nsColor(Theme.textTertiary))
                        } else {
                            ForEach(Array(held.enumerated()), id: \.offset) { _, key in Cap(key: key) }
                        }
                    } else if let hotkey = model.hotkey {
                        ForEach(Array(hotkey.keycaps.enumerated()), id: \.offset) { _, key in Cap(key: key) }
                    } else {
                        Text("Record Shortcut").font(uiFont(12)).foregroundStyle(nsColor(Theme.textSecondary))
                    }
                }
                .padding(.horizontal, 6)
                .frame(minWidth: 132, minHeight: 30)
                .background(RoundedRectangle(cornerRadius: 8).fill(nsColor(Theme.fg(isHovered || model.isRecording ? 0.08 : 0.05))))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(nsColor(model.isRecording ? Theme.accent : Theme.fg(0.1)), lineWidth: 1))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { isHovered = $0 }
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { recorderFrame.rect = $0 }

            if model.hotkey != .standard {
                Button { model.reset() } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(nsColor(Theme.textSecondary))
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Reset to \(Hotkey.standard.displayString)")
            }
        }
    }
}

/// Raycast's Hyper Key, when it's on: what it is and a one-click ✦ N.
private struct HyperHint: View {
    @Bindable var model: SettingsModel

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Cap(key: "✦", large: true)
            VStack(alignment: .leading, spacing: 3) {
                if let hyper = model.raycastHyper {
                    Text("Raycast's Hyper Key is on").font(uiFont(12, .medium)).foregroundStyle(nsColor(Theme.textPrimary))
                    Text("\(hyper.keyName) works as \(Hotkey.symbols(for: HyperKey.modifiers).joined()). Press it with a key while recording.")
                        .font(uiFont(11)).foregroundStyle(nsColor(Theme.textSecondary))
                } else {
                    Text("Using a Hyper Key?").font(uiFont(12, .medium)).foregroundStyle(nsColor(Theme.textPrimary))
                    Text("Turn one on in Raycast (Settings → Advanced) or Karabiner, then press it with a key while recording.")
                        .font(uiFont(11)).foregroundStyle(nsColor(Theme.textSecondary))
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if model.raycastHyper != nil, !(model.hotkey?.isHyper() ?? false) {
                Button { model.useHyper() } label: {
                    HStack(spacing: 4) {
                        Text("Use").font(uiFont(12, .medium))
                        Cap(key: "✦")
                        Cap(key: "N")
                    }
                    .foregroundStyle(nsColor(Theme.textPrimary))
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .background(RoundedRectangle(cornerRadius: 8).fill(nsColor(Theme.fg(0.08))))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(nsColor(Theme.fg(0.04))))
    }
}

/// A keycap like Raycast's `shortcut__kbd`: a hairline border, secondary text.
private struct Cap: View {
    let key: String
    var large = false

    var body: some View {
        Text(key)
            .font(uiFont(large ? 14 : 11, .medium))
            .foregroundStyle(nsColor(Theme.textSecondary))
            .padding(.horizontal, 5)
            .frame(minWidth: large ? 28 : 20, minHeight: large ? 28 : 20, maxHeight: large ? 28 : 20)
            .overlay(RoundedRectangle(cornerRadius: large ? 7 : 5).strokeBorder(nsColor(Theme.fg(0.2)), lineWidth: 1))
    }
}

private func uiFont(_ size: CGFloat, _ weight: Fonts.Weight = .regular) -> Font {
    Font(Fonts.ui(size: size, weight: weight) as CTFont)
}

private func nsColor(_ color: NSColor) -> Color { Color(nsColor: color) }
