import Foundation

/// Minimal convex-polygon helpers, enough to measure how much of the canvas a
/// transformed source rectangle actually covers.
enum ConvexPolygon {

    /// Twice the signed area. Positive for counter-clockwise winding in a y-down space
    /// (which reads as clockwise on screen), negative for the other.
    static func signedDoubleArea(_ polygon: [Point2D]) -> Double {
        guard polygon.count >= 3 else { return 0 }
        var total = 0.0
        for i in polygon.indices {
            let p = polygon[i]
            let q = polygon[(i + 1) % polygon.count]
            total += p.x * q.y - q.x * p.y
        }
        return total
    }

    static func area(_ polygon: [Point2D]) -> Double {
        abs(signedDoubleArea(polygon)) / 2
    }

    /// Sutherland-Hodgman clip of `subject` against the convex `clip` polygon.
    ///
    /// Both polygons are re-wound consistently first, so callers do not have to care
    /// which direction an affine transform happened to flip their corners into.
    static func clip(_ subject: [Point2D], by clip: [Point2D]) -> [Point2D] {
        guard subject.count >= 3, clip.count >= 3 else { return [] }

        let clipper = signedDoubleArea(clip) < 0 ? clip.reversed().map { $0 } : clip
        var output = signedDoubleArea(subject) < 0 ? subject.reversed().map { $0 } : subject

        for i in clipper.indices {
            guard !output.isEmpty else { return [] }
            let edgeStart = clipper[i]
            let edgeEnd = clipper[(i + 1) % clipper.count]
            let input = output
            output = []

            for j in input.indices {
                let current = input[j]
                let previous = input[(j + input.count - 1) % input.count]
                let currentInside = isInside(current, edgeStart, edgeEnd)
                let previousInside = isInside(previous, edgeStart, edgeEnd)

                if currentInside {
                    if !previousInside, let x = intersection(previous, current, edgeStart, edgeEnd) {
                        output.append(x)
                    }
                    output.append(current)
                } else if previousInside, let x = intersection(previous, current, edgeStart, edgeEnd) {
                    output.append(x)
                }
            }
        }
        return output
    }

    private static func isInside(_ p: Point2D, _ edgeStart: Point2D, _ edgeEnd: Point2D) -> Bool {
        let edge = edgeEnd - edgeStart
        let toPoint = p - edgeStart
        return edge.x * toPoint.y - edge.y * toPoint.x >= 0
    }

    private static func intersection(_ p1: Point2D, _ p2: Point2D, _ q1: Point2D, _ q2: Point2D) -> Point2D? {
        let r = p2 - p1
        let s = q2 - q1
        let denominator = r.x * s.y - r.y * s.x
        guard abs(denominator) > 1e-12 else { return nil }
        let t = ((q1.x - p1.x) * s.y - (q1.y - p1.y) * s.x) / denominator
        return Point2D(p1.x + t * r.x, p1.y + t * r.y)
    }
}
