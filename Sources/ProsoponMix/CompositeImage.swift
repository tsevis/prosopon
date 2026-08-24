import CoreGraphics
import Foundation
import ProsoponIO

/// Assembles the four quadrants into one flat image.
///
/// Used twice: for the small preview that makes a composite something you can look at
/// without opening Photoshop, and for the optional full-size flat export when the
/// composites are final and the layers were never going to be touched.
///
/// It draws from the tiles rather than from the document the writer produced, which is a
/// duplication worth naming: the two could in principle disagree. They are checked against
/// each other by `scripts/validate_psd.py --mix`, which compares the document's own stored
/// composite against the same tiles.
public enum CompositeImage {

    public static func render(
        tiles: [Quadrant: URL], grid: QuadrantGrid, size: Int
    ) throws -> CGImage {
        let half = size / 2
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else {
            throw MixWriteError.previewFailed("could not create a \(size) x \(size) context")
        }

        // White under everything, as the document's background layer is.
        context.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: size, height: size))

        for quadrant in Quadrant.allCases {
            guard let tile = tiles[quadrant] else { continue }
            // Decoded at the size actually needed. For a 512 px preview that is a
            // thumbnail rather than a 2048 px decode per quadrant, which is the
            // difference between a preview costing nothing and costing as much as the
            // document.
            let image = size < grid.canvasSize
                ? try ImageLoading.thumbnail(tile, maxPixelSize: size)
                : try ImageLoading.load(tile)
            let scale = Double(image.width) / Double(grid.canvasSize)
            let origin = grid.origin(of: quadrant)
            let region = CGRect(
                x: Double(origin.x) * scale, y: Double(origin.y) * scale,
                width: Double(grid.quadrantSize) * scale,
                height: Double(grid.quadrantSize) * scale
            )
            guard let cropped = image.cropping(to: region) else {
                throw MixWriteError.previewFailed("could not crop \(tile.lastPathComponent)")
            }
            // Core Graphics draws from a bottom-left origin, so the top row of the canvas
            // is the far edge of the context.
            context.draw(cropped, in: CGRect(
                x: origin.x == 0 ? 0 : half,
                y: origin.y == 0 ? half : 0,
                width: half, height: half
            ))
        }

        guard let image = context.makeImage() else {
            throw MixWriteError.previewFailed("the assembled composite would not render")
        }
        return image
    }
}
