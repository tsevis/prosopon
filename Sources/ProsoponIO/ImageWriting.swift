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

public enum ImageWriting {

    /// Writes `image`, converting the linear working space back to sRGB on the way out.
    public static func write(_ image: CGImage, to url: URL, format: ImageFormat) throws {
        let output = convertToOutputSpace(image) ?? image

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
    private static func convertToOutputSpace(_ image: CGImage) -> CGImage? {
        guard let srgb = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil,
                width: image.width,
                height: image.height,
                bitsPerComponent: 16,
                bytesPerRow: 0,
                space: srgb,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder16Little.rawValue
              )
        else { return nil }

        context.setBlendMode(.copy)
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return context.makeImage()
    }
}
