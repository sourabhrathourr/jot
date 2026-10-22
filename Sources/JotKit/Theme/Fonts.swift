import AppKit
import CoreText

/// Bundled InterVariable + JetBrains Mono, set up the way Raycast's CSS uses them:
/// `font-family: InterVariable`, `font-optical-sizing: none` (opsz stays at 14),
/// `font-synthesis: none`, features `liga calt kern ss03` everywhere plus `ss01` in the
/// editor.
///
/// Two details verified against Raycast's pixels:
/// - Inter's static Regular is ~0.4% narrower than the variable font at wght 400.
/// - The editor CSS also lists `tnum`, but WebKit's output matches *without* it (word
///   positions identical to the pixel); in CoreText `tnum` also narrows Inter's space.
///   Tabular figures are only used where Raycast's CSS asks via `font-variant-numeric`.
nonisolated enum Fonts {
    enum Weight {
        case regular, medium, semibold

        var value: CGFloat {
            switch self {
            case .regular: 400
            case .medium: 500
            case .semibold: 600
            }
        }
    }

    private static let wghtAxis = 0x7767_6874 // 'wght'
    private static let opszAxis = 0x6F70_737A // 'opsz'
    private static let baseFeatures: [(String, Int)] = [("liga", 1), ("calt", 1), ("kern", 1), ("ss03", 1)]
    private static let editorFeatures = baseFeatures + [("ss01", 1)]

    static func registerBundledFonts() {
        guard let directory = fontsDirectory,
              let urls = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        else { return }
        let fonts = urls.filter { $0.pathExtension == "ttf" } as CFArray
        CTFontManagerRegisterFontURLs(fonts, .process, true, nil)
    }

    /// Editor text (`.notes-editor__editor`): base features + `tnum ss01`.
    static func inter(size: CGFloat, weight: Weight = .regular, italic: Bool = false, tabularNumbers: Bool = false) -> NSFont {
        variableInter(size: size, weight: weight, italic: italic, features: editorFeatures + (tabularNumbers ? [("tnum", 1)] : []))
    }

    /// Chrome text (title, counter, menus): the `:root` base features only.
    /// List titles turn `calt` off (`standard-list-item__title { font-feature-settings: base, "calt" 0 }`).
    static func ui(size: CGFloat, weight: Weight = .regular, tabularNumbers: Bool = false, contextualAlternates: Bool = true) -> NSFont {
        var features = baseFeatures + (tabularNumbers ? [("tnum", 1)] : [])
        if !contextualAlternates { features = features.map { $0.0 == "calt" ? ("calt", 0) : $0 } }
        return variableInter(size: size, weight: weight, italic: false, features: features)
    }

    static func mono(size: CGFloat, bold: Bool = false, italic: Bool = false) -> NSFont {
        let name = bold ? "JetBrainsMono-Bold" : italic ? "JetBrainsMono-Italic" : "JetBrainsMono-Regular"
        return NSFont(name: name, size: size)
            ?? NSFont.monospacedSystemFont(ofSize: size, weight: bold ? .semibold : .regular)
    }

    private static func variableInter(size: CGFloat, weight: Weight, italic: Bool, features: [(String, Int)]) -> NSFont {
        guard let base = NSFont(name: italic ? "InterVariableItalic" : "InterVariable", size: size) else {
            return NSFont.systemFont(ofSize: size, weight: weight.systemWeight)
        }
        let tagKey = NSFontDescriptor.FeatureKey(rawValue: kCTFontOpenTypeFeatureTag as String)
        let valueKey = NSFontDescriptor.FeatureKey(rawValue: kCTFontOpenTypeFeatureValue as String)
        let descriptor = base.fontDescriptor.addingAttributes([
            .variation: [NSNumber(value: wghtAxis): NSNumber(value: Double(weight.value)), NSNumber(value: opszAxis): NSNumber(value: 14)],
            .featureSettings: features.map { [tagKey: $0.0, valueKey: $0.1] as [NSFontDescriptor.FeatureKey: Any] },
        ])
        return NSFont(descriptor: descriptor, size: size) ?? base
    }

    private static var fontsDirectory: URL? {
        if let url = Bundle.main.resourceURL?.appendingPathComponent("Fonts"),
           FileManager.default.fileExists(atPath: url.path) {
            return url
        }
        return Bundle.module.url(forResource: "Fonts", withExtension: nil)
    }
}

nonisolated private extension Fonts.Weight {
    var systemWeight: NSFont.Weight {
        switch self {
        case .regular: .regular
        case .medium: .medium
        case .semibold: .semibold
        }
    }
}
