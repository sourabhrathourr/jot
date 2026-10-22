import Foundation
import ServiceManagement

/// "Open at Login" (SMAppService), so Jot is already in the menu bar after a restart and its
/// shortcut works right away. On by default, set up the first time Jot runs from /Applications;
/// dev builds elsewhere never register themselves.
enum LoginItem {
    private static let didSetUpKey = "didSetUpLoginItem"

    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    /// macOS wants the user's OK in System Settings → General → Login Items.
    static var needsApproval: Bool { SMAppService.mainApp.status == .requiresApproval }

    static var isInstalled: Bool { Bundle.main.bundleURL.path.hasPrefix("/Applications/") }

    static func setEnabled(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            FileHandle.standardError.write(Data("Jot: couldn't \(enabled ? "add" : "remove") the login item (\(error))\n".utf8))
        }
    }

    /// The default: open at login, once, for an installed copy.
    static func setUpOnFirstLaunch() {
        guard isInstalled, !UserDefaults.standard.bool(forKey: didSetUpKey) else { return }
        UserDefaults.standard.set(true, forKey: didSetUpKey)
        if !isEnabled { setEnabled(true) }
    }
}
