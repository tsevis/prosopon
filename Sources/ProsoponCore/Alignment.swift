import Foundation

/// The result of an alignment solve: the transform, plus everything needed to judge
/// whether the result is good enough to put in a mosaic.
public struct Alignment: Hashable, Sendable, Codable {
    /// Source pixel space to canvas pixel space.
    public let transform: Affine2D

    /// The eyes-only similarity stage, before stretch and shear. Kept for diagnostics
    /// and for the `rigid` comparison view.
    public let similarity: Affine2D

    /// Vertical scale the mouth target demanded, before clamping.
    public let requestedStretch: Double
    /// Vertical scale actually applied.
    public let appliedStretch: Double
    /// Shear the mouth target demanded, before clamping.
    public let requestedShear: Double
    /// Shear actually applied.
    public let appliedShear: Double

    /// Signed canvas-space error of the mouth: `actual - target`. Zero on both axes
    /// when neither clamp bit is set.
    public let mouthResidual: Point2D

    /// Largest canvas-space error across the two eyes. Structurally ~0 — the solve
    /// pins the eyes by construction — so a non-trivial value here means a bug.
    public let eyeResidual: Double

    public var stretchWasClamped: Bool { abs(requestedStretch - appliedStretch) > 1e-9 }
    public var shearWasClamped: Bool { abs(requestedShear - appliedShear) > 1e-9 }

    /// Percentage stretch actually applied, signed. +4.2 means the face was made 4.2 % taller.
    public var appliedStretchPercent: Double { (appliedStretch - 1) * 100 }
    /// Percentage stretch the face wanted. Compare against `maxStretch` to see how hard it hit the cap.
    public var requestedStretchPercent: Double { (requestedStretch - 1) * 100 }

    /// Output pixels per source pixel along the axis of greatest magnification.
    /// Above 1.0 the source is being enlarged and the tile will be soft.
    public var magnification: Double { transform.singularValues.0 }

    /// Clockwise-positive roll removed from the face, in degrees.
    public var rollCorrectionDegrees: Double {
        -atan2(similarity.b, similarity.a) * 180 / .pi
    }
}
