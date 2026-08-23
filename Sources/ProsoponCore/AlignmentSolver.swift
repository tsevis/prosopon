import Foundation

public enum AlignmentFailure: Error, Hashable, Sendable {
    /// The two eye landmarks coincide, or very nearly. No scale or rotation is recoverable.
    case degenerateEyes(separation: Double)
    /// The mouth landed on or above the eye line in canvas space: the face is upside
    /// down, or the landmarks are mislabelled.
    case mouthNotBelowEyeLine(canvasY: Double)
}

/// Solves for the affine that carries a face's three landmarks onto the canvas targets.
///
/// The solve runs in two stages, and the split is the whole trick:
///
/// 1. **Similarity from the eyes alone.** Closed form, no optimiser. This lands both
///    eyes exactly on target and leaves the face upright in canvas space.
///
/// 2. **Stretch and shear about the eye line.** Both operations pivot on `y = 512`,
///    where the eyes already sit — so the vertical scale cannot move them, and the
///    shear displacement `h * (y - 512)` is identically zero there. The eyes stay
///    exact *for free*, with no least-squares step and no drift, and the clamps
///    become directly reportable: "wanted 7.3 % stretch, allowed 5 %, mouth 31 px high".
///
/// Because the stretch is vertical-only, the aspect-ratio change is exactly the
/// stretch factor, so the 5 % rule reads literally off `appliedStretch`. Splitting the
/// distortion across both axes would halve the visible per-axis error at constant
/// area, but any horizontal scale about x = 1024 moves the eyes off 512 and 1536.
public enum AlignmentSolver {

    public static func solve(
        landmarks: FaceLandmarks,
        spec: CanvasSpec = .standard,
        options: SolveOptions = .default
    ) throws -> Alignment {

        let similarity = try eyeSimilarity(landmarks: landmarks, spec: spec)

        let mouthInCanvas = similarity.apply(to: landmarks.mouth)
        let drop = mouthInCanvas.y - spec.eyeLineY
        guard drop > 1e-6 else {
            throw AlignmentFailure.mouthNotBelowEyeLine(canvasY: mouthInCanvas.y)
        }

        let requestedStretch = spec.mouthDrop / drop
        let appliedStretch = requestedStretch.clamped(to: options.stretchRange)

        let requestedShear = options.correctsHorizontalMouthOffset
            ? (spec.mouth.x - mouthInCanvas.x) / drop
            : 0
        let appliedShear = requestedShear.clamped(to: -options.maxShear...options.maxShear)

        let correction = stretchAndShear(
            stretch: appliedStretch,
            shear: appliedShear,
            aboutY: spec.eyeLineY
        )
        let transform = similarity.concatenating(correction)

        let mouthActual = transform.apply(to: landmarks.mouth)
        let leftActual = transform.apply(to: landmarks.viewerLeftEye)
        let rightActual = transform.apply(to: landmarks.viewerRightEye)

        return Alignment(
            transform: transform,
            similarity: similarity,
            requestedStretch: requestedStretch,
            appliedStretch: appliedStretch,
            requestedShear: requestedShear,
            appliedShear: appliedShear,
            mouthResidual: mouthActual - spec.mouth,
            eyeResidual: max(
                leftActual.distance(to: spec.viewerLeftEye),
                rightActual.distance(to: spec.viewerRightEye)
            )
        )
    }

    /// The unique similarity carrying both eye landmarks exactly onto their targets.
    ///
    /// Derived directly rather than through atan2 and a scale: for eye vector `v` and
    /// target vector `u`, the linear part `[[p, -q], [q, p]]` with `p = (v·u)/|v|²`
    /// and `q = (v x u)/|v|²` maps `v` to `u` exactly and is a similarity by construction.
    private static func eyeSimilarity(landmarks: FaceLandmarks, spec: CanvasSpec) throws -> Affine2D {
        let v = landmarks.viewerRightEye - landmarks.viewerLeftEye
        let lengthSquared = v.x * v.x + v.y * v.y
        guard lengthSquared > 1e-12 else {
            throw AlignmentFailure.degenerateEyes(separation: lengthSquared.squareRoot())
        }

        let u = spec.viewerRightEye - spec.viewerLeftEye
        let p = (v.x * u.x + v.y * u.y) / lengthSquared
        let q = (v.x * u.y - v.y * u.x) / lengthSquared

        let linear = Affine2D(a: p, b: q, c: -q, d: p, tx: 0, ty: 0)
        let mapped = linear.apply(to: landmarks.viewerLeftEye)
        let offset = spec.viewerLeftEye - mapped

        return Affine2D(a: p, b: q, c: -q, d: p, tx: offset.x, ty: offset.y)
    }

    /// `[[1, h], [0, s]]` pivoted on the eye line, as an affine.
    ///
    ///     x' = x + h * (y - pivot)
    ///     y' = pivot + s * (y - pivot)
    static func stretchAndShear(stretch s: Double, shear h: Double, aboutY pivot: Double) -> Affine2D {
        Affine2D(a: 1, b: 0, c: h, d: s, tx: -h * pivot, ty: pivot * (1 - s))
    }
}

extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
