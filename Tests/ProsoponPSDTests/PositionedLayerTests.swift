import CoreGraphics
import Foundation
import ProsoponIO
import Testing
@testable import ProsoponPSD

/// Layers that occupy part of the canvas rather than all of it.
///
/// This is what a quartered composite is made of, and it is what replaces layer masks:
/// the layer record already carries a bounding rectangle, so a quadrant is a quarter-sized
/// layer at a quarter-sized offset and no mask section has to exist.
@Suite("Positioned layers")
struct PositionedLayerTests {

    private let canvas = 64
    private let quadrant = 32

    private func directory() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("prosopon-quadrant-\(UInt64.random(in: 0...UInt64.max))")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// A flat tile of one colour, written to disk the way an aligned tile would be.
    private func tile(_ color: (Double, Double, Double), side: Int, at url: URL) throws {
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try #require(CGContext(
            data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
            space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(red: color.0, green: color.1, blue: color.2, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: side, height: side))
        try ImageWriting.write(try #require(context.makeImage()), to: url, format: .png, depth: .eight)
    }

    /// Four differently coloured quadrant layers on one canvas, in the reference
    /// document's order: top-left, top-right, bottom-left, bottom-right.
    private func quarteredDocument(in folder: URL) throws -> PSDDocument {
        let colors: [(Double, Double, Double)] = [(1, 0, 0), (0, 1, 0), (0, 0, 1), (1, 1, 0)]
        let origins = [(0, 0), (quadrant, 0), (0, quadrant), (quadrant, quadrant)]
        let names = ["top-left", "top-right", "bottom-left", "bottom-right"]

        var layers: [PSDLayer] = []
        for index in 0..<4 {
            let url = folder.appendingPathComponent("\(names[index]).png")
            try tile(colors[index], side: quadrant, at: url)
            layers.append(PSDLayer(
                name: names[index],
                frame: LayerFrame(x: origins[index].0, y: origins[index].1,
                                  width: quadrant, height: quadrant),
                content: .image(url)
            ))
        }
        return PSDDocument(width: canvas, height: canvas, layers: layers)
    }

    // MARK: Frames

    @Test("each layer declares its own quadrant rather than the whole canvas")
    func quadrantRects() throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let output = folder.appendingPathComponent("quartered.psd")

        _ = try StackWriter.write(try quarteredDocument(in: folder), to: output,
                                  options: StackOptions(format: .psd))

        let report = try DocumentInspector.inspect(output)
        #expect(report.width == canvas && report.height == canvas)
        // Records are stored bottom-to-top, so the caller's first layer comes last.
        let byName = Dictionary(uniqueKeysWithValues: report.layers.map { ($0.name, $0) })
        #expect(try #require(byName["top-left"]).rect == (0, 0, quadrant, quadrant))
        #expect(try #require(byName["top-right"]).rect == (0, quadrant, quadrant, canvas))
        #expect(try #require(byName["bottom-left"]).rect == (quadrant, 0, canvas, quadrant))
        #expect(try #require(byName["bottom-right"]).rect == (quadrant, quadrant, canvas, canvas))
    }

    @Test("the flattened composite puts each quadrant in its own quarter",
          arguments: [Compression.rle, .raw])
    func compositeAssembly(compression: Compression) throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let output = folder.appendingPathComponent("quartered.psd")

        _ = try StackWriter.write(
            try quarteredDocument(in: folder), to: output,
            options: StackOptions(format: .psd, depth: .eight, compression: compression)
        )

        let report = try DocumentInspector.inspect(output)
        let centre = quadrant / 2
        #expect(report.mergedPixel(x: centre, y: centre)?.r == 255, "top-left is red")
        #expect(report.mergedPixel(x: quadrant + centre, y: centre)?.g == 255, "top-right is green")
        #expect(report.mergedPixel(x: centre, y: quadrant + centre)?.b == 255, "bottom-left is blue")
        let bottomRight = try #require(report.mergedPixel(x: quadrant + centre, y: quadrant + centre))
        #expect(bottomRight.r == 255 && bottomRight.g == 255 && bottomRight.b == 0, "bottom-right is yellow")
    }

    // MARK: Hidden layers

    @Test("a hidden layer is flagged hidden and stays out of the flattened result")
    func hiddenLayersDoNotComposite() throws {
        // The markers in the reference document are hidden, and Photoshop computes its
        // composite from what is visible. A stored composite that included them would be
        // wrong in whatever opened the file next.
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let output = folder.appendingPathComponent("marked.psd")

        var document = try quarteredDocument(in: folder)
        let marker = PSDLayer(
            name: "left eye",
            frame: LayerFrame(x: 12, y: 12, width: 8, height: 8),
            content: .disc(RGBA8(red: 128, green: 128, blue: 0)),
            isVisible: false
        )
        document.layers.insert(marker, at: 0)

        _ = try StackWriter.write(document, to: output, options: StackOptions(format: .psd))

        let report = try DocumentInspector.inspect(output)
        let written = try #require(report.layers.first { $0.name == "left eye" })
        #expect(written.isVisible == false)
        #expect(written.rect == (12, 12, 20, 20))
        #expect(report.layers.filter(\.isVisible).count == 4, "only the four quadrants show")

        // Dead centre of the marker, which is inside the red top-left quadrant.
        let under = try #require(report.mergedPixel(x: 16, y: 16))
        #expect(under.r == 255 && under.g == 0 && under.b == 0,
                "the hidden marker reached the composite")
    }

    @Test("a locked layer records the lock")
    func lockedBackground() throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let output = folder.appendingPathComponent("background.psd")

        let document = PSDDocument(width: canvas, height: canvas, layers: [
            PSDLayer(
                name: "Background",
                frame: .canvas(width: canvas, height: canvas),
                content: .solid(.white),
                isLocked: true
            )
        ])
        _ = try StackWriter.write(document, to: output, options: StackOptions(format: .psd))

        let report = try DocumentInspector.inspect(output)
        let background = try #require(report.layers.first)
        #expect(background.isLocked)
        #expect(background.isVisible)
        let pixel = try #require(report.mergedPixel(x: 1, y: 1))
        #expect(pixel.r == 255 && pixel.g == 255 && pixel.b == 255 && pixel.a == 255)
    }

    // MARK: Cropped content

    @Test("a cropped layer takes the region of the file that matches where it sits")
    func croppedQuadrantsKeepTheirOrientation() throws {
        // The one that catches a flipped or mirrored crop. A quartered composite works
        // only because quadrant (1, 1) of an aligned face lands on quadrant (1, 1) of the
        // canvas: take the wrong quarter, or take it upside down, and every seam is
        // meaningless while the file still opens perfectly happily.
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }

        // One tile, four quarters, four colours: top-left red, top-right green,
        // bottom-left blue, bottom-right yellow.
        let source = folder.appendingPathComponent("quartered-source.png")
        try quarteredTile(side: canvas, to: source)

        // Each layer takes its *own* quarter of that tile and puts it back where it came
        // from, so the composite should reproduce the source exactly.
        let origins: [(Int, Int)] = [(0, 0), (quadrant, 0), (0, quadrant), (quadrant, quadrant)]
        let layers = origins.map { origin in
            PSDLayer(
                name: "\(origin.0),\(origin.1)",
                frame: LayerFrame(x: origin.0, y: origin.1, width: quadrant, height: quadrant),
                content: .croppedImage(source, x: origin.0, y: origin.1)
            )
        }

        let output = folder.appendingPathComponent("cropped.psd")
        _ = try StackWriter.write(
            PSDDocument(width: canvas, height: canvas, layers: layers),
            to: output, options: StackOptions(format: .psd)
        )

        let report = try DocumentInspector.inspect(output)
        let centre = quadrant / 2
        let topLeft = try #require(report.mergedPixel(x: centre, y: centre))
        #expect(topLeft.r > 200 && topLeft.g < 40, "top-left should still be red")
        let topRight = try #require(report.mergedPixel(x: quadrant + centre, y: centre))
        #expect(topRight.g > 200 && topRight.r < 40, "top-right should still be green")
        let bottomLeft = try #require(report.mergedPixel(x: centre, y: quadrant + centre))
        #expect(bottomLeft.b > 200 && bottomLeft.r < 40, "bottom-left should still be blue")
        let bottomRight = try #require(report.mergedPixel(x: quadrant + centre, y: quadrant + centre))
        #expect(bottomRight.r > 200 && bottomRight.g > 200 && bottomRight.b < 40,
                "bottom-right should still be yellow")
    }

    @Test("a crop that runs off the edge of its file is refused by name")
    func cropOutOfBounds() throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("small.png")
        try tile((1, 0, 0), side: quadrant, at: source)

        let document = PSDDocument(width: canvas, height: canvas, layers: [
            PSDLayer(
                name: "off the edge",
                frame: LayerFrame(x: quadrant, y: quadrant, width: quadrant, height: quadrant),
                content: .croppedImage(source, x: quadrant, y: quadrant)
            )
        ])
        #expect(throws: PSDWriteError.self) {
            try StackWriter.write(document, to: folder.appendingPathComponent("bad.psd"))
        }
    }

    /// One tile with a different flat colour in each quarter, described from the top left.
    private func quarteredTile(side: Int, to url: URL) throws {
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try #require(CGContext(
            data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
            space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        let half = side / 2
        // Core Graphics counts y from the bottom, so the top row is drawn last.
        let quarters: [(CGRect, (Double, Double, Double))] = [
            (CGRect(x: 0, y: half, width: half, height: half), (1, 0, 0)),        // top-left
            (CGRect(x: half, y: half, width: half, height: half), (0, 1, 0)),     // top-right
            (CGRect(x: 0, y: 0, width: half, height: half), (0, 0, 1)),           // bottom-left
            (CGRect(x: half, y: 0, width: half, height: half), (1, 1, 0)),        // bottom-right
        ]
        for (rect, color) in quarters {
            context.setFillColor(red: color.0, green: color.1, blue: color.2, alpha: 1)
            context.fill(rect)
        }
        try ImageWriting.write(try #require(context.makeImage()), to: url, format: .png, depth: .eight)
    }

    // MARK: Generated content

    @Test("a disc is round: opaque at its centre, empty at its corner")
    func discShape() throws {
        let buffer = PixelBuffer.disc(width: 16, height: 16, depth: .eight,
                                      color: RGBA8(red: 128, green: 128, blue: 0))
        let planes = buffer.planarChannels(depth: .eight)
        let alpha = planes[3]
        #expect(alpha[8 * 16 + 8] == 255, "the centre is solid")
        #expect(alpha[0] == 0, "the corner is empty")
        #expect(planes[0][8 * 16 + 8] == 128, "and it is the colour asked for")
    }

    @Test("an empty frame is refused rather than written as a zero-byte channel")
    func emptyFrameRejected() throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let output = folder.appendingPathComponent("empty.psd")

        let document = PSDDocument(width: canvas, height: canvas, layers: [
            PSDLayer(name: "nothing", frame: LayerFrame(x: 0, y: 0, width: 0, height: 0),
                     content: .solid(.white))
        ])
        #expect(throws: PSDWriteError.self) {
            try StackWriter.write(document, to: output)
        }
    }
}
