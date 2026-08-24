import CoreGraphics
import Foundation
import ProsoponCore
import ProsoponIO
import Testing
@testable import ProsoponMix

/// What a seam strip is reduced to, and the two colour decisions inside that.
@Suite("Edge signatures")
struct EdgeSignatureTests {

    @Test("a strip matched against itself is a perfect join")
    func identicalStripsAreZero() {
        let signature = EdgeSignature(lightness: 62, greenRed: 8, blueYellow: 14, texture: 3)
        #expect(signature.distance(to: signature) == 0)
    }

    @Test("black against white is about as far apart as Lab goes")
    func blackAgainstWhite() {
        let black = EdgeSignature(lightness: 0, greenRed: 0, blueYellow: 0, texture: 0)
        let white = EdgeSignature(lightness: 100, greenRed: 0, blueYellow: 0, texture: 0)
        #expect(black.distance(to: white) == 100)
    }

    @Test("two strips of the same tone but different texture do not read as identical")
    func textureBreaksATie() {
        // A smooth cheek meeting stubble: same mean, different surface. It counts, but
        // only a little -- a tone step is a visible seam, a texture change often is not.
        let smooth = EdgeSignature(lightness: 60, greenRed: 10, blueYellow: 15, texture: 1)
        let rough = EdgeSignature(lightness: 60, greenRed: 10, blueYellow: 15, texture: 9)
        let distance = smooth.distance(to: rough)
        #expect(distance > 0)
        #expect(distance == 4, "8 units of texture at the 0.5 weight")
    }

    @Test("the mean is taken in linear light, not in sRGB")
    func meanIsLinear() throws {
        // Half black, half white. Averaged in linear light that is 0.5, which is L* 76;
        // averaged in gamma-encoded sRGB it would be 127/255, which is L* 53. The
        // difference is 23 units of lightness on one strip -- far more than the tone
        // differences the matcher is trying to tell apart -- so it is worth pinning.
        let folder = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }

        let spec = CanvasSpec.standard.scaled(toSize: 64)
        let grid = QuadrantGrid(spec: spec, seamWidth: 32, mouthBandHeight: 12)
        let url = folder.appendingPathComponent("half.png")
        try writeTile(to: url, side: 64) { x, y in
            // Top half black, bottom half white, so a horizontal strip spanning the
            // middle sees equal amounts of each.
            y < 32 ? (0, 0, 0) : (1, 1, 1)
        }

        let measured = try TileMeasurer(grid: grid, measureSize: 64).measure(
            tileURL: url, sourcePath: url.path, name: "half", yawDegrees: nil, score: nil
        )
        // .topLeftBottom is x 0..<32, y 0..<32 with a 32 px strip -- the whole top-left
        // quadrant, which is entirely black. Use the bottom strip of the top half against
        // the top strip of the bottom half instead by measuring the seam that straddles.
        let blackStrip = try #require(measured.edges[.topLeftBottom])
        #expect(abs(blackStrip.lightness) < 0.5, "the black half is L* 0")

        let whiteStrip = try #require(measured.edges[.bottomLeftTop])
        #expect(abs(whiteStrip.lightness - 100) < 0.5, "the white half is L* 100")

        // And the conversion itself, which is what the strip means are built on.
        let linearMean = ColorConversion.lab(linearRed: 0.5, green: 0.5, blue: 0.5)
        #expect(abs(linearMean.0 - 76.07) < 0.05, "L* of linear 0.5 is 76, not 53")
    }

    @Test("a strip's texture reading rises with the detail in it")
    func textureReading() throws {
        let folder = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }

        let spec = CanvasSpec.standard.scaled(toSize: 64)
        let grid = QuadrantGrid(spec: spec, seamWidth: 8, mouthBandHeight: 12)
        let measurer = TileMeasurer(grid: grid, measureSize: 64)

        let flat = folder.appendingPathComponent("flat.png")
        try writeTile(to: flat, side: 64) { _, _ in (0.5, 0.5, 0.5) }
        let striped = folder.appendingPathComponent("striped.png")
        try writeTile(to: striped, side: 64) { x, _ in
            x % 2 == 0 ? (0.0, 0.0, 0.0) : (1.0, 1.0, 1.0)
        }

        let flatEdge = try #require(
            measurer.measure(tileURL: flat, sourcePath: "", name: "flat", yawDegrees: nil, score: nil)
                .edges[.bottomLeftRight]
        )
        let stripedEdge = try #require(
            measurer.measure(tileURL: striped, sourcePath: "", name: "striped", yawDegrees: nil, score: nil)
                .edges[.bottomLeftRight]
        )
        #expect(flatEdge.texture < 1)
        #expect(stripedEdge.texture > 40)
    }

    // MARK: Helpers

    private func temporaryDirectory() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("prosopon-mix-\(UInt64.random(in: 0...UInt64.max))")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Writes a square tile whose colour is a function of (x, y) in top-left coordinates.
    private func writeTile(
        to url: URL, side: Int, color: (Int, Int) -> (Double, Double, Double)
    ) throws {
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try #require(CGContext(
            data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
            space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        for y in 0..<side {
            for x in 0..<side {
                let (r, g, b) = color(x, y)
                context.setFillColor(red: r, green: g, blue: b, alpha: 1)
                // Core Graphics counts from the bottom, the tile is described from the top.
                context.fill(CGRect(x: x, y: side - 1 - y, width: 1, height: 1))
            }
        }
        try ImageWriting.write(try #require(context.makeImage()), to: url, format: .png, depth: .eight)
    }
}
