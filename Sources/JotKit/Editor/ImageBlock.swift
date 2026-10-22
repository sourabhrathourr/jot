import AppKit

extension NSPasteboard.PasteboardType {
    /// An image block being dragged within a note: "<attachment id>|<character index>".
    static let jotImageMove = NSPasteboard.PasteboardType("com.sourabh.jot.image-move")
}

extension Notification.Name {
    /// A decode finished; `object` is the attachment id. Editors redraw the blocks showing it.
    static let jotImageDecoded = Notification.Name("jot.imageDecoded")
}

/// The one character of an image block. It only reserves the space (`attachmentBounds`);
/// `BlockLayoutFragment` draws the image from `ImageCache`, so an image costs one bitmap at
/// display size and no view.
nonisolated final class ImageAttachment: NSTextAttachment {
    let ref: ImageRef
    /// Set by the editor; the fragment draws the selection outline from it.
    var isSelected = false

    init(_ ref: ImageRef) {
        self.ref = ref
        super.init(data: nil, ofType: nil)
        allowsTextAttachmentView = false
    }

    required init?(coder: NSCoder) { fatalError() }

    /// Raycast's `.imageBlock` sizing: `min(width, 640, 480 × aspect)`, never wider than the
    /// text, in CSS pixels (so a pixel of the image is a point on screen). An image without
    /// a known size gets the 320pt loading box.
    static func displaySize(_ ref: ImageRef, available: CGFloat) -> CGSize {
        guard let w = ref.width, let h = ref.height, w > 0, h > 0 else {
            return CGSize(width: min(320, available), height: 180)
        }
        let aspect = CGFloat(w) / CGFloat(h)
        let width = min(CGFloat(w), 640, 480 * aspect, max(1, available)).rounded()
        return CGSize(width: width, height: (width / aspect).rounded())
    }

    override func attachmentBounds(
        for attributes: [NSAttributedString.Key: Any],
        location: any NSTextLocation,
        textContainer: NSTextContainer?,
        proposedLineFragment: CGRect,
        position: CGPoint
    ) -> CGRect {
        CGRect(origin: .zero, size: Self.displaySize(ref, available: proposedLineFragment.width))
    }

    /// The fragment draws the image; an empty image keeps TextKit from drawing a placeholder icon.
    private static let blank = NSImage(size: NSSize(width: 1, height: 1))

    override func image(for bounds: CGRect, attributes: [NSAttributedString.Key: Any], location: any NSTextLocation, textContainer: NSTextContainer?) -> NSImage? {
        Self.blank
    }
}

/// Draws an image block inside its layout fragment: the bitmap in an 8pt rounded clip,
/// Raycast's 2pt `--color-text-secondary` outline when selected, or "Couldn't load image".
nonisolated enum ImageBlockRenderer {
    static func draw(_ attachment: ImageAttachment, in frame: CGRect, url: URL?, context: CGContext) {
        let scale = max(1, abs(context.userSpaceToDeviceSpaceTransform.a))
        if let url {
            let pixels = ImageCache.bucket(max(frame.width, frame.height) * scale)
            if let image = ImageCache.shared.cached(url, maxPixels: pixels) {
                context.saveGState()
                context.addPath(CGPath(roundedRect: frame, cornerWidth: 8, cornerHeight: 8, transform: nil))
                context.clip()
                // Fragments draw in a flipped space; CGImages draw upright in an unflipped one.
                context.translateBy(x: frame.minX, y: frame.maxY)
                context.scaleBy(x: 1, y: -1)
                context.interpolationQuality = .high
                context.draw(image, in: CGRect(origin: .zero, size: frame.size))
                context.restoreGState()
            } else if ImageCache.shared.failed(url) {
                drawStatus("Couldn't load image", in: frame, context: context)
            } else {
                ImageCache.shared.prefetch(url, maxPixels: pixels, id: attachment.ref.attachmentId)
            }
        } else {
            drawStatus("Couldn't load image", in: frame, context: context)
        }

        if attachment.isSelected {
            context.saveGState()
            context.addPath(CGPath(roundedRect: frame.insetBy(dx: -1, dy: -1), cornerWidth: 9, cornerHeight: 9, transform: nil))
            context.setStrokeColor(Theme.textSecondary.cgColor)
            context.setLineWidth(2)
            context.strokePath()
            context.restoreGState()
        }
    }

    private static func drawStatus(_ text: String, in frame: CGRect, context: CGContext) {
        let string = NSAttributedString(string: text, attributes: [.font: Fonts.ui(size: 13), .foregroundColor: Theme.textSecondary])
        let size = string.size()
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        string.draw(at: CGPoint(x: frame.midX - size.width / 2, y: frame.midY - size.height / 2))
        NSGraphicsContext.restoreGraphicsState()
    }
}
