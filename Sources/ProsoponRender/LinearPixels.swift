import CoreGraphics
import Foundation

/// A rectangle of premultiplied RGBA samples in **linear** light, 16 bits per channel.
///
/// Resampling has to happen in linear light. Filtering gamma-encoded values darkens
/// every edge, and across a stack of hundreds of aligned faces that systematic
/// darkening lands exactly on the lash lines and lip edges the alignment exists to
/// preserve. Core Graphics does the decode on the way in, when the source is drawn
/// into a linear context.
struct LinearPixels {
    let width: Int
    let height: Int
    var samples: [UInt16]

    static func empty(width: Int, height: Int) -> LinearPixels {
        LinearPixels(width: width, height: height, samples: [UInt16](repeating: 0, count: width * height * 4))
    }

    private static var linearSpace: CGColorSpace? { CGColorSpace(name: CGColorSpace.linearSRGB) }

    private static var bitmapInfo: UInt32 {
        CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder16Little.rawValue
    }

    /// Decodes the given region of `image` into linear light.
    ///
    /// Only the region the canvas actually reaches is decoded. A 6000 px source would
    /// otherwise cost nearly 300 MB per image in this representation, times however
    /// many images are in flight.
    static func decode(
        _ image: CGImage,
        cropX: Int, cropY: Int, width: Int, height: Int
    ) -> LinearPixels? {
        guard width > 0, height > 0, let space = linearSpace else { return nil }

        var pixels = empty(width: width, height: height)
        let drawn = pixels.samples.withUnsafeMutableBytes { raw -> Bool in
            guard let context = CGContext(
                data: raw.baseAddress, width: width, height: height,
                bitsPerComponent: 16, bytesPerRow: width * 8,
                space: space, bitmapInfo: bitmapInfo
            ) else { return false }

            context.setBlendMode(.copy)
            // Core Graphics is bottom-left origin; every coordinate here is top-left.
            context.translateBy(x: 0, y: Double(height))
            context.scaleBy(x: 1, y: -1)
            context.translateBy(x: -Double(cropX), y: -Double(cropY))
            // And the same flip again for the image's own pixel space.
            context.translateBy(x: 0, y: Double(image.height))
            context.scaleBy(x: 1, y: -1)
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            return true
        }
        return drawn ? pixels : nil
    }

    /// Wraps the samples as a CGImage tagged linear, so a later conversion to sRGB
    /// applies the transfer function exactly once.
    func makeCGImage() -> CGImage? {
        guard let space = Self.linearSpace else { return nil }
        let data = samples.withUnsafeBufferPointer { Data(buffer: $0) }
        guard let provider = CGDataProvider(data: data as CFData) else { return nil }
        return CGImage(
            width: width, height: height,
            bitsPerComponent: 16, bitsPerPixel: 64, bytesPerRow: width * 8,
            space: space, bitmapInfo: CGBitmapInfo(rawValue: Self.bitmapInfo),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        )
    }
}
