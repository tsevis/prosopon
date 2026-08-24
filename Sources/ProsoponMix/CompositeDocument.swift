import Foundation
import ProsoponCore
import ProsoponPSD

/// Turns one composite's four tiles into the layer stack that gets written.
///
/// The arrangement follows the reference document built by hand: the three landmark
/// markers hidden on top, then the four quadrants in reading order, then a white
/// background. The quadrants do not overlap, so their order is cosmetic — it is kept
/// anyway, because a document that opens looking like the one it was modelled on is
/// easier to trust.
///
/// No masks. Each quadrant is a 1024 x 1024 layer at its own offset, cropped out of the
/// aligned tile as it is written. That costs a quarter of what four full-canvas layers
/// would, and gives up the ability to slide a seam in Photoshop afterwards — a deliberate
/// trade, recorded in docs/PLAN.md.
public enum CompositeDocument {

    public static func make(
        tiles: [Quadrant: URL],
        names: [Quadrant: String],
        grid: QuadrantGrid,
        spec: CanvasSpec = .standard,
        options: MixOptions = .default
    ) -> PSDDocument {
        var layers: [PSDLayer] = []

        if options.includesMarkers {
            layers.append(contentsOf: markers(spec: spec))
        }

        for quadrant in [Quadrant.topLeft, .topRight, .bottomLeft, .bottomRight] {
            guard let tile = tiles[quadrant] else { continue }
            let origin = grid.origin(of: quadrant)
            layers.append(PSDLayer(
                name: names[quadrant] ?? quadrant.label,
                frame: LayerFrame(
                    x: origin.x, y: origin.y,
                    width: grid.quadrantSize, height: grid.quadrantSize
                ),
                // The layer takes the same region of the tile that it occupies on the
                // canvas, which is the whole reason the tiles are aligned: quadrant (1, 1)
                // of one face lands on quadrant (1, 1) of the canvas, pixel for pixel.
                content: .croppedImage(tile, x: origin.x, y: origin.y)
            ))
        }

        if options.includesBackground {
            layers.append(PSDLayer(
                name: "Background",
                frame: .canvas(width: grid.canvasSize, height: grid.canvasSize),
                content: .solid(.white),
                isLocked: true
            ))
        }

        return PSDDocument(width: grid.canvasSize, height: grid.canvasSize, layers: layers)
    }

    /// The three landmark markers, hidden, topmost, in the reference document's order.
    private static func markers(spec: CanvasSpec) -> [PSDLayer] {
        let points: [(String, Point2D)] = [
            ("mouth", spec.mouth),
            ("right eye", spec.viewerRightEye),
            ("left eye", spec.viewerLeftEye),
        ]
        let size = MarkerStyle.diameter
        return points.map { name, point in
            PSDLayer(
                name: name,
                frame: LayerFrame(
                    x: Int(point.x.rounded()) - size / 2,
                    y: Int(point.y.rounded()) - size / 2,
                    width: size, height: size
                ),
                content: .disc(MarkerStyle.color),
                isVisible: false
            )
        }
    }
}
