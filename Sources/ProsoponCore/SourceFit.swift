import Foundation

/// How well a given source image, under a given alignment, actually fills the canvas.
///
/// This is the gate that matters most for mosaic work: a tile with transparent
/// corners is unusable, so anything short of complete coverage is rejected outright
/// rather than padded.
public struct SourceFit: Hashable, Sendable, Codable {
    /// Fraction of the canvas backed by real source pixels, 0...1.
    public let coverage: Double
    /// True when all four canvas corners fall inside the source image.
    public let isFullyCovered: Bool
    /// The canvas corners mapped back into source space, in canvas-corner order.
    /// This is the crop rectangle the photo would need to have had.
    public let sourceQuad: [Point2D]

    public var coveragePercent: Double { coverage * 100 }

    /// Evaluates coverage for `alignment` against a source image of `sourceSize` pixels.
    public static func evaluate(
        alignment: Alignment,
        sourceWidth: Double,
        sourceHeight: Double,
        spec: CanvasSpec = .standard
    ) -> SourceFit {
        guard let inverse = alignment.transform.inverted else {
            return SourceFit(coverage: 0, isFullyCovered: false, sourceQuad: [])
        }

        let quad = spec.corners.map { inverse.apply(to: $0) }
        let fullyCovered = quad.allSatisfy {
            $0.x >= 0 && $0.y >= 0 && $0.x <= sourceWidth && $0.y <= sourceHeight
        }

        let sourceRectInCanvas = [
            Point2D(0, 0), Point2D(sourceWidth, 0),
            Point2D(sourceWidth, sourceHeight), Point2D(0, sourceHeight),
        ].map { alignment.transform.apply(to: $0) }

        let overlap = ConvexPolygon.clip(spec.corners, by: sourceRectInCanvas)
        let coverage = ConvexPolygon.area(overlap) / (spec.size * spec.size)

        return SourceFit(
            coverage: min(1, max(0, coverage)),
            isFullyCovered: fullyCovered,
            sourceQuad: quad
        )
    }
}
