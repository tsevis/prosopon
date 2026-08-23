import CoreGraphics
import Foundation
import ProsoponCore

/// Lanczos-3 resampling on the CPU.
///
/// This is the reference implementation: the GPU kernel is checked against it tap for
/// tap, so the two must stay in step. It is also the fallback where Metal is absent.
public struct CPULanczosRenderer: TileRenderer {
    public let spec: CanvasSpec

    public init(spec: CanvasSpec = .standard) {
        self.spec = spec
    }

    public func render(_ image: CGImage, using transform: Affine2D) throws -> CGImage {
        let side = Int(spec.size.rounded())
        let plan = try WarpPlan.make(
            transform: transform,
            sourceWidth: image.width, sourceHeight: image.height,
            canvasSize: side
        )

        var output = LinearPixels.empty(width: side, height: side)
        guard !plan.isEmpty else {
            guard let empty = output.makeCGImage() else { throw RenderError.contextUnavailable }
            return empty
        }

        guard let source = LinearPixels.decode(
            image, cropX: plan.cropX, cropY: plan.cropY,
            width: plan.cropWidth, height: plan.cropHeight
        ) else { throw RenderError.contextUnavailable }

        Warp.resample(source: source, into: &output, plan: plan, sourceOrigin: (plan.cropX, plan.cropY),
                      fullSourceWidth: image.width, fullSourceHeight: image.height)

        guard let result = output.makeCGImage() else { throw RenderError.contextUnavailable }
        return result
    }
}

/// The gather loop, shared in spirit with the Metal kernel in `WarpShader`.
enum Warp {
    static func resample(
        source: LinearPixels,
        into output: inout LinearPixels,
        plan: WarpPlan,
        sourceOrigin: (x: Int, y: Int),
        fullSourceWidth: Int,
        fullSourceHeight: Int
    ) {
        let inverse = plan.inverse
        let maxSample = 65535.0

        source.samples.withUnsafeBufferPointer { src in
            output.samples.withUnsafeMutableBufferPointer { dst in
                for row in 0..<output.height {
                    for column in 0..<output.width {
                        let destination = Point2D(Double(column) + 0.5, Double(row) + 0.5)
                        let point = inverse.apply(to: destination)

                        let index = (row * output.width + column) * 4
                        // A centre outside the photograph gets nothing, rather than an
                        // edge colour smeared into space that was never photographed.
                        guard point.x >= 0, point.y >= 0,
                              point.x < Double(plan.cropWidth), point.y < Double(plan.cropHeight)
                        else {
                            dst[index] = 0; dst[index + 1] = 0; dst[index + 2] = 0; dst[index + 3] = 0
                            continue
                        }

                        var total = (r: 0.0, g: 0.0, b: 0.0, a: 0.0)
                        var weightSum = 0.0

                        let firstY = Int((point.y - plan.supportY - 0.5).rounded(.down)) + 1
                        let lastY = Int((point.y + plan.supportY - 0.5).rounded(.down))
                        let firstX = Int((point.x - plan.supportX - 0.5).rounded(.down)) + 1
                        let lastX = Int((point.x + plan.supportX - 0.5).rounded(.down))

                        for y in firstY...max(firstY, lastY) {
                            let wy = Lanczos.weight((Double(y) + 0.5 - point.y) * plan.kernelScaleY)
                            if wy == 0 { continue }
                            let clampedY = min(max(y, 0), plan.cropHeight - 1)
                            for x in firstX...max(firstX, lastX) {
                                let wx = Lanczos.weight((Double(x) + 0.5 - point.x) * plan.kernelScaleX)
                                if wx == 0 { continue }
                                let clampedX = min(max(x, 0), plan.cropWidth - 1)
                                let weight = wx * wy
                                let tap = (clampedY * source.width + clampedX) * 4
                                total.r += weight * Double(src[tap])
                                total.g += weight * Double(src[tap + 1])
                                total.b += weight * Double(src[tap + 2])
                                total.a += weight * Double(src[tap + 3])
                                weightSum += weight
                            }
                        }

                        guard weightSum > 0 else {
                            dst[index] = 0; dst[index + 1] = 0; dst[index + 2] = 0; dst[index + 3] = 0
                            continue
                        }

                        // Renormalising absorbs the clamped taps at the source edge, so
                        // the border neither darkens nor brightens.
                        let alpha = min(max(total.a / weightSum, 0), maxSample)
                        func channel(_ value: Double) -> UInt16 {
                            // Lanczos overshoots at edges; premultiplied data stays valid
                            // only while every colour channel remains within alpha.
                            UInt16(min(max(value / weightSum, 0), alpha).rounded())
                        }
                        dst[index] = channel(total.r)
                        dst[index + 1] = channel(total.g)
                        dst[index + 2] = channel(total.b)
                        dst[index + 3] = UInt16(alpha.rounded())
                    }
                }
            }
        }
    }
}
