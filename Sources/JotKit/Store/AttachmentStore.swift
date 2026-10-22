import Foundation
import ImageIO
import Synchronization
import UniformTypeIdentifiers

/// Image files beside the database, in `Attachments/<id>.<ext>`. A file is written once and
/// never changed, so notes (and copies of notes) can share it by id. Notes are only ever
/// soft-deleted, so files are kept for as long as the database is.
nonisolated final class AttachmentStore: Sendable {
    enum Failure: Error {
        case notAnImage
    }

    let directory: URL
    /// id → file, so lookups don't touch the disk after the first time.
    private let files = Mutex<[String: URL]>([:])

    init(directory: URL) {
        self.directory = directory
    }

    /// `Attachments` next to the notes database.
    static func directory(forDatabase path: String) -> URL {
        URL(fileURLWithPath: path).deletingLastPathComponent().appendingPathComponent("Attachments", isDirectory: true)
    }

    // MARK: Adding

    /// Stores image data and returns its reference. Formats macOS can't share well (TIFF,
    /// BMP) become PNG; everything else (PNG, JPEG, HEIC, GIF, WebP…) is kept byte for byte.
    func add(_ data: Data) throws -> ImageRef {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let type = CGImageSourceGetType(source).map({ UTType($0 as String) }) ?? nil,
              CGImageSourceGetCount(source) > 0
        else { throw Failure.notAnImage }

        let (width, height) = Self.pixelSize(source)
        let id = ULID.make()
        var bytes = data
        var ext = type.preferredFilenameExtension ?? "img"
        if type.conforms(to: .tiff) || type.conforms(to: .bmp) {
            bytes = try Self.png(from: source)
            ext = "png"
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("\(id).\(ext)")
        try bytes.write(to: url, options: .atomic)
        files.withLock { $0[id] = url }
        return ImageRef(attachmentId: id, width: width, height: height)
    }

    func add(contentsOf file: URL) throws -> ImageRef {
        try add(Data(contentsOf: file, options: .mappedIfSafe))
    }

    // MARK: Reading

    func url(for id: String) -> URL? {
        if let url = files.withLock({ $0[id] }) { return url }
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        guard let name = names.first(where: { $0.hasPrefix(id + ".") }) else { return nil }
        let url = directory.appendingPathComponent(name)
        files.withLock { $0[id] = url }
        return url
    }

    // MARK: Helpers

    /// The displayed size: EXIF orientations 5–8 rotate the image a quarter turn.
    private static func pixelSize(_ source: CGImageSource) -> (Int?, Int?) {
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
        let width = properties[kCGImagePropertyPixelWidth] as? Int
        let height = properties[kCGImagePropertyPixelHeight] as? Int
        let orientation = properties[kCGImagePropertyOrientation] as? Int ?? 1
        return orientation >= 5 ? (height, width) : (width, height)
    }

    private static func png(from source: CGImageSource) throws -> Data {
        guard let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { throw Failure.notAnImage }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
            throw Failure.notAnImage
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw Failure.notAnImage }
        return data as Data
    }
}
