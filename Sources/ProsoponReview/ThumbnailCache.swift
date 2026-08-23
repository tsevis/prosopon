import CoreGraphics
import Foundation
import ImageIO

/// Carries a CGImage across a task boundary.
///
/// Core Graphics images are immutable once created and safe to hand between threads,
/// but they carry no `Sendable` conformance, so the compiler needs telling.
public struct SendableImage: @unchecked Sendable {
    public let image: CGImage
    public init(_ image: CGImage) { self.image = image }
}

/// Small thumbnails for the tile list, decoded straight to size.
///
/// ImageIO can decode a reduced image without ever materialising the full 2048 square,
/// which is what makes a list of several hundred tiles scroll rather than crawl.
public actor ThumbnailCache {
    private var cache: [URL: SendableImage] = [:]
    private let maximumPixelSize: Int

    public init(maximumPixelSize: Int = 180) {
        self.maximumPixelSize = maximumPixelSize
    }

    public func thumbnail(for url: URL) -> SendableImage? {
        if let existing = cache[url] { return existing }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        let wrapped = SendableImage(image)
        cache[url] = wrapped
        return wrapped
    }

    public func invalidate(_ url: URL) { cache[url] = nil }
    public func invalidateAll() { cache.removeAll() }
}
