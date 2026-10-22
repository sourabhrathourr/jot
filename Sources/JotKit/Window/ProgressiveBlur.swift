import AppKit

/// Raycast's `ProgressiveBlur` (`progressive-blur` module), used under the notes header as
/// `height: 52, position: top`: nine stacked backdrop blurs of increasing radius, each
/// masked to a band that moves up by 12.5% per level, so content gets blurrier toward the
/// top edge.
///
/// CSS `backdrop-filter` maps to Core Animation's private `CABackdropLayer` with a
/// `gaussianBlur` `CAFilter`, the same machinery `NSVisualEffectView` is built on. If either
/// class is unavailable the view draws nothing and the header keeps the plain fade.
final class ProgressiveBlurView: NSView {
    /// `blurLevels` default, in CSS px (= points).
    static let levels: [CGFloat] = [0.25, 0.5, 0.75, 1, 1.4, 1.8, 2.3, 2.9, 3.6]

    private struct Band {
        let backdrop: CALayer
        let mask = CAGradientLayer()
        /// (fraction from the top, mask alpha), as written in Raycast's gradients.
        let stops: [(CGFloat, CGFloat)]
    }

    private var bands: [Band] = []

    override init(frame: NSRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        guard ProcessInfo.processInfo.environment["JOT_NO_HEADER_BLUR"] == nil,
              let backdropClass = NSClassFromString("CABackdropLayer") as? CALayer.Type,
              let filterClass = NSClassFromString("CAFilter") as? NSObject.Type else { return }
        let makeFilter = NSSelectorFromString("filterWithType:")
        guard filterClass.responds(to: makeFilter) else { return }

        for (index, radius) in Self.levels.enumerated() {
            guard let filter = filterClass.perform(makeFilter, with: "gaussianBlur")?.takeUnretainedValue() as? NSObject else { return }
            filter.setValue(radius, forKey: "inputRadius")
            filter.setValue(true, forKey: "inputNormalizeEdges")

            let backdrop = backdropClass.init()
            backdrop.filters = [filter]
            if backdrop.responds(to: NSSelectorFromString("setScale:")) {
                backdrop.setValue(1.0, forKey: "scale")
            }
            let band = Band(backdrop: backdrop, stops: Self.stops(forLevel: index))
            band.backdrop.mask = band.mask
            layer?.addSublayer(band.backdrop)
            bands.append(band)
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    /// The `position: top` masks:
    /// - first level: `linear-gradient(#0000 62.5%, #000 75% 87.5%, #0000 100%)`
    /// - level r in the middle: `linear-gradient(to top, #0000 s%, #000 (s+12.5)% (s+25)%,
    ///   #0000 (s+37.5)%)` with s = 12.5·r, measured from the bottom
    /// - last level: `linear-gradient(#000 0%, #0000 12.5%)`
    private static func stops(forLevel index: Int) -> [(CGFloat, CGFloat)] {
        if index == 0 { return [(0.625, 0), (0.75, 1), (0.875, 1), (1, 0)] }
        if index == levels.count - 1 { return [(0, 1), (0.125, 0)] }
        let s = CGFloat(index) * 0.125
        // Converted to fractions from the top.
        return [(1 - s - 0.375, 0), (1 - s - 0.25, 1), (1 - s - 0.125, 1), (1 - s, 0)]
    }

    /// CSS gradients clamp to the end colours outside their stops; Core Animation needs
    /// locations within 0…1, so the band is resampled at every stop that falls inside.
    private static func resampled(_ stops: [(CGFloat, CGFloat)]) -> [(CGFloat, CGFloat)] {
        func alpha(at t: CGFloat) -> CGFloat {
            guard let first = stops.first, let last = stops.last else { return 0 }
            if t <= first.0 { return first.1 }
            if t >= last.0 { return last.1 }
            for (a, b) in zip(stops, stops.dropFirst()) where t <= b.0 {
                return a.1 + (b.1 - a.1) * (t - a.0) / (b.0 - a.0)
            }
            return last.1
        }
        let positions = Set([0, 1] + stops.map(\.0).filter { $0 > 0 && $0 < 1 }).sorted()
        return positions.map { ($0, alpha(at: $0)) }
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for band in bands {
            band.backdrop.frame = bounds
            band.mask.frame = bounds
            let stops = Self.resampled(band.stops)
            // Unit space runs bottom-up unless the layer's contents are flipped.
            let flipped = band.mask.contentsAreFlipped()
            band.mask.startPoint = CGPoint(x: 0.5, y: flipped ? 0 : 1)
            band.mask.endPoint = CGPoint(x: 0.5, y: flipped ? 1 : 0)
            band.mask.colors = stops.map { NSColor.black.withAlphaComponent($0.1).cgColor }
            band.mask.locations = stops.map { NSNumber(value: Double($0.0)) }
        }
        CATransaction.commit()
    }
}
