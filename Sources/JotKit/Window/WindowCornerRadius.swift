import AppKit
import ObjectiveC

/// Raycast's `NSWindow+CustomizableCornerRadius`: AppKit's theme frame clips the
/// window, draws its border and casts its shadow with the system corner radius
/// (16pt on macOS 26/27). Overriding the frame's private radius getters for our
/// panels gives the window the same 26pt corners as Raycast Notes.
///
/// On macOS 27 the frame derives `_cornerRadii` (and so the mask, border and shadow)
/// from `_getCachedDefaultWindowCornerRadius`, so both getters are overridden.
enum WindowCornerRadius {
    private static var installed = false

    static func install(on window: NSWindow) {
        guard let frameView = window.contentView?.superview else { return }
        if !installed, let frameClass = NSClassFromString("NSThemeFrame") {
            installed = true
            for name in ["_cornerRadius", "_getCachedDefaultWindowCornerRadius"] {
                override(name, on: frameClass)
            }
        }
        let refresh = NSSelectorFromString("windowCornerMaskChanged")
        if frameView.responds(to: refresh) { frameView.perform(refresh) }
        frameView.needsDisplay = true
        window.invalidateShadow()
    }

    private static func override(_ name: String, on frameClass: AnyClass) {
        let selector = NSSelectorFromString(name)
        guard let method = class_getInstanceMethod(frameClass, selector) else { return }
        typealias Original = @convention(c) (NSView, Selector) -> CGFloat
        let original = unsafeBitCast(method_getImplementation(method), to: Original.self)
        let replacement: @convention(block) (NSView) -> CGFloat = { view in
            MainActor.assumeIsolated {
                (view.window as? CornerRadiusProviding)?.customCornerRadius ?? original(view, selector)
            }
        }
        method_setImplementation(method, imp_implementationWithBlock(replacement))
    }
}

protocol CornerRadiusProviding: NSWindow {
    var customCornerRadius: CGFloat { get }
}

extension NotesPanel: CornerRadiusProviding {
    var customCornerRadius: CGFloat { Layout.windowCornerRadius }
}
