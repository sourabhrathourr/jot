import AppKit
import ImageIO
import Synchronization

/// Decoded images at display size. Decoding happens off the main thread with ImageIO's
/// thumbnailer, which reads only as much of the file as the requested size needs and applies
/// EXIF orientation; a 4000px photo shown at 480pt costs a 960px bitmap, not the whole file.
/// `@unchecked`: `NSCache` is thread-safe but isn't annotated `Sendable`; the rest is behind a `Mutex`.
nonisolated final class ImageCache: @unchecked Sendable {
    static let shared = ImageCache()

    private final class Entry: @unchecked Sendable {
        let image: CGImage
        init(_ image: CGImage) { self.image = image }
    }

    private let cache: NSCache<NSString, Entry> = {
        let cache = NSCache<NSString, Entry>()
        cache.totalCostLimit = 256 * 1024 * 1024
        return cache
    }()

    /// One decode per key, however many views ask for it at once.
    private let inFlight = Mutex<[String: Task<CGImage?, Never>]>([:])
    /// Files that couldn't be decoded (missing or corrupt).
    private let failures = Mutex<Set<String>>([])
    private let prefetching = Mutex<Set<String>>([])

    /// Sizes are rounded up to 256px steps so a window resize reuses what's decoded.
    static func bucket(_ pixels: CGFloat) -> Int {
        max(256, Int((pixels / 256).rounded(.up)) * 256)
    }

    private func key(_ url: URL, _ maxPixels: Int) -> String { "\(url.path)#\(maxPixels)" }

    /// A decoded image already in memory, for drawing without a placeholder frame.
    func cached(_ url: URL, maxPixels: Int) -> CGImage? {
        cache.object(forKey: key(url, maxPixels) as NSString)?.image
    }

    func failed(_ url: URL) -> Bool {
        failures.withLock { $0.contains(url.path) }
    }

    /// Starts a decode for drawing code that can't wait; posts `.jotImageDecoded` (object: `id`)
    /// on the main thread when it's ready (or has failed).
    func prefetch(_ url: URL, maxPixels: Int, id: String) {
        let key = key(url, maxPixels)
        guard prefetching.withLock({ $0.insert(key).inserted }) else { return }
        Task {
            let image = await self.image(url, maxPixels: maxPixels)
            if image == nil { failures.withLock { _ = $0.insert(url.path) } }
            prefetching.withLock { _ = $0.remove(key) }
            await MainActor.run { NotificationCenter.default.post(name: .jotImageDecoded, object: id) }
        }
    }

    func image(_ url: URL, maxPixels: Int) async -> CGImage? {
        let key = key(url, maxPixels)
        if let hit = cache.object(forKey: key as NSString) { return hit.image }
        let task = inFlight.withLock { tasks in
            if let running = tasks[key] { return running }
            let task = Task.detached(priority: .userInitiated) { Self.decode(url, maxPixels: maxPixels) }
            tasks[key] = task
            return task
        }
        let image = await task.value
        inFlight.withLock { _ = $0.removeValue(forKey: key) }
        if let image {
            cache.setObject(Entry(image), forKey: key as NSString, cost: image.bytesPerRow * image.height)
        }
        return image
    }

    private static func decode(_ url: URL, maxPixels: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) else {
            return nil
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}
