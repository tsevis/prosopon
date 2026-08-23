import Foundation

/// The fixed output geometry every portrait is mapped onto.
///
/// The three target coordinates are **not negotiable** — mosaics are assembled from
/// quadrants of different aligned portraits, so a tile from photo A only butts
/// cleanly against a tile from photo B if both put the eyes and mouth on exactly
/// the same pixels.
///
/// Note the naming: `viewerLeftEye` is the eye that appears on the *left of the
/// image*, which is the subject's **right** eye. Apple's Vision framework and
/// InsightFace both name their landmark regions from the subject's point of view,
/// so the swap has to happen explicitly at every detector boundary.
public struct CanvasSpec: Hashable, Sendable, Codable {
    public let size: Double
    public let gridStep: Double
    public let viewerLeftEye: Point2D
    public let viewerRightEye: Point2D
    public let mouth: Point2D

    public init(size: Double, gridStep: Double, viewerLeftEye: Point2D, viewerRightEye: Point2D, mouth: Point2D) {
        self.size = size
        self.gridStep = gridStep
        self.viewerLeftEye = viewerLeftEye
        self.viewerRightEye = viewerRightEye
        self.mouth = mouth
    }

    /// 2048 x 2048, 128 px grid, eyes at (512,512) and (1536,512), mouth at (1024,1664).
    public static let standard = CanvasSpec(
        size: 2048,
        gridStep: 128,
        viewerLeftEye: Point2D(512, 512),
        viewerRightEye: Point2D(1536, 512),
        mouth: Point2D(1024, 1664)
    )

    /// The same proportions at a different output resolution. Useful for re-rendering
    /// a stack at 4096 from stored transforms without re-detecting anything.
    public func scaled(toSize newSize: Double) -> CanvasSpec {
        let k = newSize / size
        return CanvasSpec(
            size: newSize,
            gridStep: gridStep * k,
            viewerLeftEye: viewerLeftEye * k,
            viewerRightEye: viewerRightEye * k,
            mouth: mouth * k
        )
    }

    /// Distance between the two eye targets: 1024 px on the standard canvas.
    public var interocularDistance: Double { viewerRightEye.distance(to: viewerLeftEye) }

    /// The y of the eye line: 512 px. This is the pivot that keeps both eyes fixed
    /// while the mouth is corrected.
    public var eyeLineY: Double { viewerLeftEye.y }

    /// Eye line to mouth: 1152 px on the standard canvas.
    public var mouthDrop: Double { mouth.y - eyeLineY }

    /// 1.125 on the standard canvas — the proportion every face is forced toward.
    public var mouthDropRatio: Double { mouthDrop / interocularDistance }

    public var corners: [Point2D] {
        [Point2D(0, 0), Point2D(size, 0), Point2D(size, size), Point2D(0, size)]
    }
}
