import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum ImageFormat: String, CaseIterable, Sendable {
    case png
    case tiff

    var contentType: UTType {
        switch self {
        case .png: .png
        case .tiff: .tiff
        }
    }

    public var fileExtension: String { rawValue }
}

public enum ImageWriteError: Error, CustomStringConvertible {
    case destinationUnavailable(URL)
    case finalizeFailed(URL)

    public var description: String {
        switch self {
        case .destinationUnavailable(let url): "cannot create an image destination at \(url.path)"
        case .finalizeFailed(let url): "failed writing \(url.lastPathComponent)"
        }
    }
}

/// Bits per channel in a written file.
///
/// 16 is the safe default, but it only pays when the source carried more than 8 bits.
/// A tile rendered from an 8-bit JPEG or PNG stores nothing extra at 16 and costs twice
/// the disk, which matters at a few thousand tiles.
public enum OutputDepth: Int, Sendable, CaseIterable {
    case eight = 8
    case sixteen = 16
}

public enum ImageWriting {

    /// Writes `image`, converting the linear working space back to sRGB on the way out.
    public static func write(
        _ image: CGImage, to url: URL, format: ImageFormat, depth: OutputDepth = .sixteen
    ) throws {
        let output = convertToOutputSpace(image, depth: depth) ?? image

        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL, format.contentType.identifier as CFString, 1, nil
        ) else {
            throw ImageWriteError.destinationUnavailable(url)
        }

        let options: [CFString: Any] = [
            kCGImagePropertyHasAlpha: true,
            kCGImageDestinationLossyCompressionQuality: 1.0,
        ]
        CGImageDestinationAddImage(destination, output, options as CFDictionary)

        guard CGImageDestinationFinalize(destination) else {
            throw ImageWriteError.finalizeFailed(url)
        }
    }

    /// Re-encodes linear values as sRGB. Without this the file looks washed out
    /// everywhere except in software that honours the linear profile.
    private static func convertToOutputSpace(_ image: CGImage, depth: OutputDepth) -> CGImage? {
        let bitmapInfo = depth == .sixteen
            ? CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder16Little.rawValue
            : CGImageAlphaInfo.premultipliedLast.rawValue
        guard let srgb = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil,
                width: image.width,
                height: image.height,
                bitsPerComponent: depth.rawValue,
                bytesPerRow: 0,
                space: srgb,
                bitmapInfo: bitmapInfo
              )
        else { return nil }

        context.setBlendMode(.copy)
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return context.makeImage()
    }
}
