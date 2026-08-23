import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum ImageLoadError: Error, CustomStringConvertible {
    case unreadable(URL)
    case noImage(URL)

    public var description: String {
        switch self {
        case .unreadable(let url): "cannot read an image from \(url.lastPathComponent)"
        case .noImage(let url): "no decodable image in \(url.lastPathComponent)"
        }
    }
}

public enum ImageLoading {

    /// File extensions worth attempting. ImageIO handles far more than this, but the
    /// list keeps directory scans from trying to decode sidecars and text files.
    public static let recognisedExtensions: Set<String> = [
        "jpg", "jpeg", "png", "tif", "tiff", "heic", "heif", "webp",
        "dng", "cr2", "cr3", "nef", "arw", "raf", "orf", "rw2", "psd",
    ]

    /// Decodes an image with its EXIF orientation already baked into the pixels, so
    /// every coordinate downstream lives in one unambiguous top-left, y-down space.
    public static func load(_ url: URL) throws -> CGImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            throw ImageLoadError.unreadable(url)
        }
        guard let decoded = CGImageSourceCreateImageAtIndex(
            source, 0, [kCGImageSourceShouldCache: false] as CFDictionary
        ) else {
            throw ImageLoadError.noImage(url)
        }

        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let rawOrientation = properties?[kCGImagePropertyOrientation] as? UInt32 ?? 1
        guard let orientation = CGImagePropertyOrientation(rawValue: rawOrientation), rawOrientation != 1 else {
            return decoded
        }
        return bakeOrientation(orientation, into: decoded) ?? decoded
    }

    /// Redraws `image` so that the given EXIF orientation becomes the identity.
    private static func bakeOrientation(_ orientation: CGImagePropertyOrientation, into image: CGImage) -> CGImage? {
        let width = Double(image.width)
        let height = Double(image.height)
        let swapsAxes: Bool
        switch orientation {
        case .left, .leftMirrored, .right, .rightMirrored: swapsAxes = true
        default: swapsAxes = false
        }
        let outputWidth = Int(swapsAxes ? height : width)
        let outputHeight = Int(swapsAxes ? width : height)

        guard let space = image.colorSpace,
              let context = CGContext(
                data: nil,
                width: outputWidth,
                height: outputHeight,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else { return nil }

        // Built in CG's bottom-left space, hence the mirroring cases reading inverted.
        var transform = CGAffineTransform.identity
        switch orientation {
        case .up: break
        case .upMirrored:
            transform = CGAffineTransform(translationX: width, y: 0).scaledBy(x: -1, y: 1)
        case .down:
            transform = CGAffineTransform(translationX: width, y: height).rotated(by: .pi)
        case .downMirrored:
            transform = CGAffineTransform(translationX: 0, y: height).scaledBy(x: 1, y: -1)
        case .left:
            transform = CGAffineTransform(translationX: 0, y: width).rotated(by: -.pi / 2)
        case .leftMirrored:
            transform = CGAffineTransform(translationX: 0, y: 0).scaledBy(x: -1, y: 1)
                .concatenating(CGAffineTransform(translationX: 0, y: width).rotated(by: -.pi / 2))
        case .right:
            transform = CGAffineTransform(translationX: height, y: 0).rotated(by: .pi / 2)
        case .rightMirrored:
            transform = CGAffineTransform(translationX: height, y: 0).rotated(by: .pi / 2)
                .concatenating(CGAffineTransform(translationX: height, y: 0).scaledBy(x: -1, y: 1))
        @unknown default: break
        }

        context.concatenate(transform)
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }

    /// Every recognised image directly inside `directory`, sorted by name.
    public static func imageURLs(in directory: URL) throws -> [URL] {
        let contents = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        return contents
            .filter { recognisedExtensions.contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }
}

extension ImageLoading {
    /// Pixel dimensions without decoding the image, honouring EXIF orientation.
    ///
    /// A stack writer has to declare the document size in the file header before it
    /// streams any pixels, and decoding every tile twice just to learn its size would
    /// double the cost of the slowest step.
    public static func dimensions(of url: URL) -> (width: Int, height: Int)? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int
        else { return nil }

        let orientation = properties[kCGImagePropertyOrientation] as? UInt32 ?? 1
        let swapsAxes = [5, 6, 7, 8].contains(Int(orientation))
        return swapsAxes ? (height, width) : (width, height)
    }
}
