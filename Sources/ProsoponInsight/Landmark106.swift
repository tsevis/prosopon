import CoreGraphics
import Foundation
import ProsoponCore

/// The 106-point landmark model, `2d106det.onnx`.
///
/// It works on a square crop around the detected box, and returns coordinates in
/// [-1, 1] relative to that crop, which are carried back to image space through the
/// inverse of the crop transform.
struct Landmark106 {
    static let inputSide = 192
    /// This model takes raw 0...255 values; only the detector rescales its input.
    static let inputMean: Float = 0
    static let inputStandardDeviation: Float = 1
    static let pointCount = 106

    /// Indices of the points this project needs, established by running the reference
    /// implementation over a set of faces and taking the ones that stayed put.
    ///
    /// The eye centre is the midpoint of the two canthi, which unlike a pupil does not
    /// move when the subject's gaze shifts. The mouth centre is the midpoint of the two
    /// commissures, which unlike a lip-seam centroid survives the mouth opening. See
    /// `docs/PLAN.md` section 5.
    enum Index {
        static let leftEyeOuterCanthus = 35
        static let leftEyeInnerCanthus = 39
        static let rightEyeOuterCanthus = 93
        static let rightEyeInnerCanthus = 89
        static let leftMouthCommissure = 52
        static let rightMouthCommissure = 61
    }

    let model: ONNXModel
    /// Bilinear, matching the resampling the model was trained behind. Measured against
    /// the reference implementation, a higher-quality filter is *worse* here: median
    /// agreement on the three canonical points falls from 3.9 to 6.3 canvas pixels.
    /// Better resampling than the training pipeline used is not better input.
    var interpolation: CGInterpolationQuality = .low

    /// All 106 points for one detected face, in source-image pixels.
    func points(in image: CGImage, box: BoundingBox) throws -> [Point2D] {
        let transform = Self.cropTransform(for: box)
        guard let tensor = ImageTensor.nchw(
            from: image, transform: transform,
            width: Self.inputSide, height: Self.inputSide,
            mean: Self.inputMean, standardDeviation: Self.inputStandardDeviation,
            interpolation: interpolation
        ) else {
            throw InsightError.inferenceFailed("could not build the landmark model's input tensor")
        }

        let outputs = try model.run(tensor, shape: [1, 3, Self.inputSide, Self.inputSide])
        guard let output = outputs.first, output.values.count >= Self.pointCount * 2 else {
            throw InsightError.unexpectedOutputs("expected at least \(Self.pointCount * 2) values")
        }
        // Some builds emit extra leading points; the 106 wanted are the trailing ones.
        let values = Array(output.values.suffix(Self.pointCount * 2))
        guard let inverse = transform.inverted else {
            throw InsightError.inferenceFailed("the crop transform is not invertible")
        }

        let half = Double(Self.inputSide) / 2
        return (0..<Self.pointCount).map { index in
            // [-1, 1] across the crop, so shift and scale to crop pixels first.
            let x = (Double(values[index * 2]) + 1) * half
            let y = (Double(values[index * 2 + 1]) + 1) * half
            return inverse.apply(to: Point2D(x, y))
        }
    }

    /// Maps the detected box onto the model's square crop.
    ///
    /// The box is squared off by its longer side and given half again as much room, so
    /// the whole face reaches the model even when the detector cropped it tightly.
    static func cropTransform(for box: BoundingBox) -> Affine2D {
        let extent = max(box.width, box.height) * 1.5
        let scale = Double(Self.inputSide) / extent
        let centre = box.center
        let half = Double(Self.inputSide) / 2
        return Affine2D(
            a: scale, b: 0, c: 0, d: scale,
            tx: half - scale * centre.x,
            ty: half - scale * centre.y
        )
    }

    /// Reduces the 106 points to the three this project aligns on.
    static func canonicalLandmarks(from points: [Point2D]) -> FaceLandmarks? {
        guard points.count == pointCount else { return nil }
        let eyeA = Point2D.midpoint(points[Index.leftEyeOuterCanthus], points[Index.leftEyeInnerCanthus])
        let eyeB = Point2D.midpoint(points[Index.rightEyeOuterCanthus], points[Index.rightEyeInnerCanthus])
        let mouth = Point2D.midpoint(
            points[Index.leftMouthCommissure], points[Index.rightMouthCommissure]
        )
        // Which eye is on the viewer's left is decided geometrically rather than by
        // trusting the model's own naming, exactly as for the Vision backend.
        let ordered = DetectedFace.orderEyesForViewer(eyeA, eyeB, mouth: mouth)
        return FaceLandmarks(
            viewerLeftEye: ordered.viewerLeft,
            viewerRightEye: ordered.viewerRight,
            mouth: mouth
        )
    }
}
