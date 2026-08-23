import CoreGraphics
import CoreText
import Foundation
import ProsoponCore
import ProsoponIO

/// A grid of tile thumbnails with the target crosshairs drawn over each one.
///
/// Numbers say which tiles disagree with the stack; this says *how*. A crosshair sitting
/// beside the pupil rather than on it is a misread landmark, and that is visible at a
/// glance across two dozen thumbnails in a way no column of figures is.
public enum ContactSheet {

    public struct Style: Sendable {
        public var cell: Int
        public var columns: Int
        public var padding: Int
        public var labelHeight: Int

        public init(cell: Int = 240, columns: Int = 6, padding: Int = 8, labelHeight: Int = 26) {
            self.cell = cell
            self.columns = columns
            self.padding = padding
            self.labelHeight = labelHeight
        }
    }

    public static func render(
        tiles: [TileQA],
        spec: CanvasSpec,
        style: Style = Style()
    ) throws -> CGImage? {
        guard !tiles.isEmpty else { return nil }

        let columns = max(1, min(style.columns, tiles.count))
        let rows = (tiles.count + columns - 1) / columns
        let cellWidth = style.cell + style.padding
        let cellHeight = style.cell + style.labelHeight + style.padding
        let width = columns * cellWidth + style.padding
        let height = rows * cellHeight + style.padding

        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: 0, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else { return nil }

        context.setFillColor(red: 0.11, green: 0.11, blue: 0.12, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        let scale = Double(style.cell) / spec.size

        for (index, tile) in tiles.enumerated() {
            let column = index % columns
            let row = index / columns
            let originX = Double(style.padding + column * cellWidth)
            // Core Graphics counts from the bottom; the grid reads from the top.
            let originY = Double(height - style.padding - (row + 1) * cellHeight + style.labelHeight)

            if let image = try? ImageLoading.load(URL(fileURLWithPath: tile.path)) {
                context.draw(image, in: CGRect(
                    x: originX, y: originY, width: Double(style.cell), height: Double(style.cell)
                ))
            }

            drawCrosshairs(in: context, originX: originX, originY: originY,
                           cell: Double(style.cell), scale: scale, spec: spec)
            drawLabel(in: context, tile: tile, originX: originX,
                      originY: originY - Double(style.labelHeight) + 8, width: Double(style.cell))
        }

        return context.makeImage()
    }

    private static func drawCrosshairs(
        in context: CGContext, originX: Double, originY: Double,
        cell: Double, scale: Double, spec: CanvasSpec
    ) {
        context.setStrokeColor(red: 0.25, green: 0.9, blue: 0.95, alpha: 0.85)
        context.setLineWidth(1)
        let arm = 9.0
        for landmark in Landmark.allCases {
            let target = landmark.target(in: spec)
            let x = originX + target.x * scale
            // The tile is upright inside the cell, so canvas y counts down from its top.
            let y = originY + cell - target.y * scale
            context.move(to: CGPoint(x: x - arm, y: y))
            context.addLine(to: CGPoint(x: x + arm, y: y))
            context.move(to: CGPoint(x: x, y: y - arm))
            context.addLine(to: CGPoint(x: x, y: y + arm))
        }
        context.strokePath()
    }

    private static func drawLabel(
        in context: CGContext, tile: TileQA, originX: Double, originY: Double, width: Double
    ) {
        let displacement = tile.worstDisplacement
        let landmark = tile.worstLandmark?.shortName ?? "-"
        let matched = tile.lowestCorrelation >= StackQA.matchFloor
        // Without a match the displacement is not a measurement, so it is not shown.
        let text = matched
            ? String(format: "%@  %.1fpx %@", shorten(tile.name, to: 18), displacement, landmark)
            : String(format: "%@  no match", shorten(tile.name, to: 22))

        // Red once a tile is far enough out to be worth opening.
        let warm = !matched || displacement > 2
        let colour = CGColor(
            srgbRed: warm ? 1.0 : 0.78, green: warm ? 0.45 : 0.78,
            blue: warm ? 0.35 : 0.80, alpha: 1
        )
        let font = CTFontCreateWithName("Menlo" as CFString, 11, nil)
        let attributes: [NSAttributedString.Key: Any] = [
            kCTFontAttributeName as NSAttributedString.Key: font,
            kCTForegroundColorAttributeName as NSAttributedString.Key: colour,
        ]
        let line = CTLineCreateWithAttributedString(
            NSAttributedString(string: text, attributes: attributes)
        )
        context.textMatrix = .identity
        context.textPosition = CGPoint(x: originX + 2, y: originY)
        CTLineDraw(line, context)
    }

    private static func shorten(_ name: String, to limit: Int) -> String {
        name.count <= limit ? name : String(name.prefix(limit - 1)) + "\u{2026}"
    }
}
