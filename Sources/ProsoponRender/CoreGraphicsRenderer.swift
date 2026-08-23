import CoreGraphics
import Foundation
import ProsoponCore

/// Rasterises a source image onto the canvas using Core Graphics' own resampler.
///
/// Kept as the reference the Metal renderer is measured against, and as the fallback
/// when no GPU is available.
///
/// The context is created in a **linear** colour space on purpose. Resampling in
/// gamma-encoded values darkens every edge, and in a stack of hundreds of faces that
/// systematic darkening compounds into visible mush along exactly the high-contrast
/// features — lash lines, lip edges — the alignment exists to preserve.
///
/// Interpolation is Core Graphics' `.high`, whose exact kernel is unspecified.
public struct CoreGraphicsRenderer: TileRenderer {
    public let spec: CanvasSpec

    public init(spec: CanvasSpec = .standard) {
        self.spec = spec
    }

    /// Pixels outside the source stay transparent, so a partially covered canvas is
    /// visibly wrong rather than quietly padded with invented content.
    public func render(_ image: CGImage, using transform: Affine2D) throws -> CGImage {
        let side = Int(spec.size.rounded())
        guard let workingSpace = CGColorSpace(name: CGColorSpace.linearSRGB),
              let context = CGContext(
                data: nil,
                width: side,
                height: side,
                bitsPerComponent: 16,
                bytesPerRow: 0,
                space: workingSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder16Little.rawValue
              )
        else { throw RenderError.contextUnavailable }

        context.interpolationQuality = .high
        context.setBlendMode(.copy)

        // Core Graphics is bottom-left origin; Prosopon's geometry is top-left, y-down.
        context.translateBy(x: 0, y: spec.size)
        context.scaleBy(x: 1, y: -1)

        context.concatenate(CGAffineTransform(
            a: transform.a, b: transform.b,
            c: transform.c, d: transform.d,
            tx: transform.tx, ty: transform.ty
        ))

        // And the same flip again for the image's own pixel space.
        let width = Double(image.width)
        let height = Double(image.height)
        context.translateBy(x: 0, y: height)
        context.scaleBy(x: 1, y: -1)
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        guard let output = context.makeImage() else { throw RenderError.contextUnavailable }
        return output
    }
}
