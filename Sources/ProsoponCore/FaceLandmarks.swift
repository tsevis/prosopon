import Foundation

/// The three points Prosopon aligns on, in source-image pixel space.
///
/// Whatever detector produced them, they must already follow the project's
/// definitions (see `docs/PLAN.md` section 5):
///
/// - eye centre = midpoint of the inner and outer canthi, which unlike the iris
///   does not move when the subject's gaze shifts;
/// - mouth centre = midpoint of the two commissures, which unlike a lip-seam
///   centroid is stable whether the mouth is open or closed.
public struct FaceLandmarks: Hashable, Sendable, Codable {
    public let viewerLeftEye: Point2D
    public let viewerRightEye: Point2D
    public let mouth: Point2D

    public init(viewerLeftEye: Point2D, viewerRightEye: Point2D, mouth: Point2D) {
        self.viewerLeftEye = viewerLeftEye
        self.viewerRightEye = viewerRightEye
        self.mouth = mouth
    }

    public var interocularDistance: Double { viewerRightEye.distance(to: viewerLeftEye) }

    public var eyeMidpoint: Point2D { .midpoint(viewerLeftEye, viewerRightEye) }

    /// The face's own eye-to-mouth proportion, measured perpendicular to the eye line.
    ///
    /// Comparing this against `CanvasSpec.mouthDropRatio` (1.125) predicts how much
    /// stretch the face will demand before any transform is built.
    public var mouthDropRatio: Double {
        let eyeAxis = viewerRightEye - viewerLeftEye
        let d = eyeAxis.length
        guard d > 0 else { return .nan }
        let unit = Point2D(eyeAxis.x / d, eyeAxis.y / d)
        let normal = Point2D(-unit.y, unit.x)
        let toMouth = mouth - eyeMidpoint
        return abs(toMouth.x * normal.x + toMouth.y * normal.y) / d
    }
}
