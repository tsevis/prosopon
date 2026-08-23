import Foundation
import ProsoponCore

/// The Lanczos-3 windowed-sinc kernel, and the geometry both renderers derive from a
/// transform before resampling.
public enum Lanczos {

    /// Half-width of the kernel in output samples.
    public static let radius = 3.0

    /// A single tap weight. `L(0) = 1` and `L(k) = 0` at every other integer, which is
    /// what makes an identity transform reproduce its input exactly.
    public static func weight(_ x: Double) -> Double {
        let magnitude = abs(x)
        guard magnitude < radius else { return 0 }
        guard magnitude > 1e-9 else { return 1 }
        let pi = Double.pi
        return (sin(pi * x) / (pi * x)) * (sin(pi * x / radius) / (pi * x / radius))
    }
}

/// Everything the resampling loop needs, derived once per tile.
struct WarpPlan {
    /// Canvas coordinates to coordinates within the cropped source region.
    let inverse: Affine2D
    let cropX: Int
    let cropY: Int
    let cropWidth: Int
    let cropHeight: Int
    /// Multiplies the distance handed to the kernel. Below 1 when the source is being
    /// reduced, which is what stretches the footprint over more source pixels.
    let kernelScaleX: Double
    let kernelScaleY: Double
    /// Footprint half-width in source pixels along each source axis.
    let supportX: Double
    let supportY: Double

    /// Beyond this the tap count becomes ruinous. A source reduced by more than about
    /// five times is already far outside what a portrait corpus produces, and doing it
    /// properly would want a mip pyramid rather than an ever-wider gather.
    static let maximumSupport = 16.0

    static func make(
        transform: Affine2D,
        sourceWidth: Int,
        sourceHeight: Int,
        canvasSize: Int
    ) throws -> WarpPlan {
        guard let inverse = transform.inverted else { throw RenderError.degenerateTransform }

        // Destination length per unit step along each source axis.
        let scaleAlongX = (transform.a * transform.a + transform.b * transform.b).squareRoot()
        let scaleAlongY = (transform.c * transform.c + transform.d * transform.d).squareRoot()

        let kernelScaleX = min(1, max(1 / maximumSupport * Lanczos.radius, scaleAlongX))
        let kernelScaleY = min(1, max(1 / maximumSupport * Lanczos.radius, scaleAlongY))
        let supportX = Lanczos.radius / kernelScaleX
        let supportY = Lanczos.radius / kernelScaleY

        // Only the part of the source the canvas actually reaches needs uploading,
        // widened by the filter footprint.
        let side = Double(canvasSize)
        let corners = [
            Point2D(0, 0), Point2D(side, 0), Point2D(side, side), Point2D(0, side),
        ].map { inverse.apply(to: $0) }

        let marginX = supportX + 1
        let marginY = supportY + 1
        let minX = max(0, Int(((corners.map(\.x).min() ?? 0) - marginX).rounded(.down)))
        let minY = max(0, Int(((corners.map(\.y).min() ?? 0) - marginY).rounded(.down)))
        let maxX = min(sourceWidth, Int(((corners.map(\.x).max() ?? 0) + marginX).rounded(.up)))
        let maxY = min(sourceHeight, Int(((corners.map(\.y).max() ?? 0) + marginY).rounded(.up)))

        let cropWidth = max(0, maxX - minX)
        let cropHeight = max(0, maxY - minY)

        return WarpPlan(
            inverse: inverse.concatenating(.translation(-Double(minX), -Double(minY))),
            cropX: minX, cropY: minY, cropWidth: cropWidth, cropHeight: cropHeight,
            kernelScaleX: kernelScaleX, kernelScaleY: kernelScaleY,
            supportX: supportX, supportY: supportY
        )
    }

    var isEmpty: Bool { cropWidth <= 0 || cropHeight <= 0 }
}
