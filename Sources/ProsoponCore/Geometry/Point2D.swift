import Foundation

/// A point in a top-left-origin, y-down pixel space.
///
/// Every coordinate in Prosopon lives in one of two such spaces: *source* space
/// (the input photograph, EXIF orientation already baked in) or *canvas* space
/// (the 2048 x 2048 output defined by `CanvasSpec`).
public struct Point2D: Hashable, Sendable, Codable {
    public var x: Double
    public var y: Double

    public init(_ x: Double, _ y: Double) {
        self.x = x
        self.y = y
    }

    public static let zero = Point2D(0, 0)

    public static func + (a: Point2D, b: Point2D) -> Point2D { Point2D(a.x + b.x, a.y + b.y) }
    public static func - (a: Point2D, b: Point2D) -> Point2D { Point2D(a.x - b.x, a.y - b.y) }
    public static func * (p: Point2D, k: Double) -> Point2D { Point2D(p.x * k, p.y * k) }

    public var length: Double { (x * x + y * y).squareRoot() }

    public func distance(to other: Point2D) -> Double { (self - other).length }

    public static func midpoint(_ a: Point2D, _ b: Point2D) -> Point2D {
        Point2D((a.x + b.x) / 2, (a.y + b.y) / 2)
    }

    /// The two points of `points` that lie farthest apart.
    ///
    /// Used to pull the eye canthi out of an eye contour and the mouth commissures
    /// out of a lip contour without depending on a detector's point ordering, which
    /// differs between Vision, InsightFace and YuNet.
    public static func extremePair(of points: [Point2D]) -> (Point2D, Point2D)? {
        guard points.count >= 2 else { return nil }
        var best = (points[0], points[1])
        var bestDistance = -1.0
        for i in 0..<(points.count - 1) {
            for j in (i + 1)..<points.count {
                let d = points[i].distance(to: points[j])
                if d > bestDistance {
                    bestDistance = d
                    best = (points[i], points[j])
                }
            }
        }
        return best
    }
}
