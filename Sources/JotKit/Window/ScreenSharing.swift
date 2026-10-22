import AppKit

/// "Hide from Screen Sharing": Jot's windows get `sharingType = .none`, which leaves them out
/// of screen sharing, recordings and screenshots (both ScreenCaptureKit, which Zoom, Meet,
/// Teams and QuickTime use, and `screencapture`), while they stay visible on your own screen.
/// Off by default, remembered across launches.
enum ScreenSharing {
    private static let key = "hideFromScreenSharing"

    static var isHidden: Bool {
        get { UserDefaults.standard.bool(forKey: key) }
        set {
            UserDefaults.standard.set(newValue, forKey: key)
            NSApp.windows.forEach(apply)
        }
    }

    /// Call for every window Jot creates; toggling updates the ones already open.
    static func apply(to window: NSWindow) {
        window.sharingType = isHidden ? .none : .readOnly
    }
}
