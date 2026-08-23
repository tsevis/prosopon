import Foundation

public struct BoundingBox: Hashable, Sendable, Codable {
    public var x, y, width, height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x; self.y = y; self.width = width; self.height = height
    }

    public var area: Double { width * height }
    public var center: Point2D { Point2D(x + width / 2, y + height / 2) }
}

/// One face found in one photograph, in source pixel space.
public struct DetectedFace: Hashable, Sendable, Codable {
    public let landmarks: FaceLandmarks
    public let boundingBox: BoundingBox
    public let confidence: Double
    /// Head pose in degrees, when the detector reports it.
    public let rollDegrees: Double?
    public let yawDegrees: Double?
    public let pitchDegrees: Double?

    public init(
        landmarks: FaceLandmarks,
        boundingBox: BoundingBox,
        confidence: Double,
        rollDegrees: Double? = nil,
        yawDegrees: Double? = nil,
        pitchDegrees: Double? = nil
    ) {
        self.landmarks = landmarks
        self.boundingBox = boundingBox
        self.confidence = confidence
        self.rollDegrees = rollDegrees
        self.yawDegrees = yawDegrees
        self.pitchDegrees = pitchDegrees
    }

    /// Orders two eye candidates so the first is the one on the **viewer's** left.
    ///
    /// Detector libraries disagree about whether "left eye" means the viewer's left or
    /// the subject's left, and getting it backwards mirrors every output. Rather than
    /// trusting a name, this decides geometrically: for eyes `a`, `b` and mouth `m`,
    /// the sign of `(b - a) x (m - a)` is positive exactly when `a` is on the viewer's
    /// left. Being a cross product it is invariant to roll, so it stays correct for a
    /// tilted or even inverted head.
    public static func orderEyesForViewer(
        _ a: Point2D, _ b: Point2D, mouth m: Point2D
    ) -> (viewerLeft: Point2D, viewerRight: Point2D) {
        let eyeAxis = b - a
        let toMouth = m - a
        let cross = eyeAxis.x * toMouth.y - eyeAxis.y * toMouth.x
        return cross > 0 ? (a, b) : (b, a)
    }
}
