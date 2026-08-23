import CoreGraphics
import Foundation
import ProsoponCore

/// Maps between canvas coordinates and the square the preview occupies on screen.
///
/// Everything the reviewer points at has to travel back through the transform to become
/// a source landmark, so this conversion sits on the path of every correction.
public struct CanvasGeometry: Equatable, Sendable {
    public let canvasSize: Double
    public let frame: CGRect

    public init(canvasSize: Double, availableSize: CGSize) {
        self.canvasSize = canvasSize
        let side = max(1, min(availableSize.width, availableSize.height))
        self.frame = CGRect(
            x: (availableSize.width - side) / 2,
            y: (availableSize.height - side) / 2,
            width: side, height: side
        )
    }

    public var scale: Double { frame.width / canvasSize }

    public func viewPoint(_ canvas: Point2D) -> CGPoint {
        CGPoint(x: frame.minX + canvas.x * scale, y: frame.minY + canvas.y * scale)
    }

    public func canvasPoint(_ view: CGPoint) -> Point2D {
        Point2D((view.x - frame.minX) / scale, (view.y - frame.minY) / scale)
    }
}
