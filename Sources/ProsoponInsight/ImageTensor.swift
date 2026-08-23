import CoreGraphics
import Foundation
import ProsoponCore

/// Turns a region of a photograph into the NCHW float tensor a model expects.
enum ImageTensor {

    /// Renders `image` through `transform` into a `width` x `height` RGB tensor.
    ///
    /// The transform is expressed in the project's top-left, y-down space, the same as
    /// everywhere else; the two flips here are what reconcile that with Core Graphics.
    /// Both models want RGB, so the channel order is fixed rather than the BGR that the
    /// reference implementation carries around from OpenCV.
    static func nchw(
        from image: CGImage,
        transform: Affine2D,
        width: Int,
        height: Int,
        mean: Float,
        standardDeviation: Float,
        interpolation: CGInterpolationQuality = .low
    ) -> [Float]? {
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = bytes.withUnsafeMutableBytes { raw -> Bool in
            guard let space = CGColorSpace(name: CGColorSpace.sRGB),
                  let context = CGContext(
                    data: raw.baseAddress, width: width, height: height,
                    bitsPerComponent: 8, bytesPerRow: width * 4, space: space,
                    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
                  )
            else { return false }

            context.setFillColor(red: 0, green: 0, blue: 0, alpha: 1)
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            context.interpolationQuality = interpolation

            context.translateBy(x: 0, y: Double(height))
            context.scaleBy(x: 1, y: -1)
            context.concatenate(CGAffineTransform(
                a: transform.a, b: transform.b, c: transform.c,
                d: transform.d, tx: transform.tx, ty: transform.ty
            ))
            context.translateBy(x: 0, y: Double(image.height))
            context.scaleBy(x: 1, y: -1)
            context.draw(image, in: CGRect(
                x: 0, y: 0, width: Double(image.width), height: Double(image.height)
            ))
            return true
        }
        guard drawn else { return nil }

        let pixels = width * height
        var tensor = [Float](repeating: 0, count: 3 * pixels)
        bytes.withUnsafeBufferPointer { source in
            tensor.withUnsafeMutableBufferPointer { destination in
                for index in 0..<pixels {
                    for channel in 0..<3 {
                        let value = Float(source[index * 4 + channel])
                        destination[channel * pixels + index] = (value - mean) / standardDeviation
                    }
                }
            }
        }
        return tensor
    }

    /// The letterbox used by the detector: fit the whole photograph into the square,
    /// anchored top-left, and leave the rest black.
    ///
    /// `margin` insets the photograph by that fraction of its shorter side first. SCRFD's
    /// anchors do not reach a face that fills its frame, so a tight crop is invisible to
    /// it until some empty space is put around the head.
    static func letterbox(
        imageWidth: Int, imageHeight: Int, side: Int, margin: Double = 0
    ) -> Affine2D {
        let inset = margin * Double(min(imageWidth, imageHeight))
        let paddedWidth = Double(imageWidth) + 2 * inset
        let paddedHeight = Double(imageHeight) + 2 * inset
        let scale = min(Double(side) / paddedWidth, Double(side) / paddedHeight)
        return Affine2D(
            a: scale, b: 0, c: 0, d: scale,
            tx: scale * inset, ty: scale * inset
        )
    }
}
