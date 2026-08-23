import CoreGraphics
import Foundation
import ProsoponCore
import Testing
import ProsoponIO
@testable import ProsoponRender

/// End-to-end checks that the *pixels* land where the maths says they should.
///
/// Every case runs against all three renderers. They differ in how they filter, but
/// not in where anything lands, so a geometry bug in one shows up immediately as a
/// disagreement with the other two.
///
/// The solver tests prove the transform is right in the abstract. These prove the
/// Core Graphics plumbing around it is right too — and that is where the real risk
/// lives, because the renderer performs two separate y-flips (canvas space, then the
/// source image's own space) and a single missing one produces output that is subtly
/// upside down or mirrored while still looking like a face.
@Suite("Render geometry")
struct RenderGeometryTests {

    /// Metal is unavailable in some CI environments; skip rather than fail there.
    static let renderers: [Resampler] = {
        let candidates: [Resampler] = [.coreGraphics, .lanczosCPU, .lanczos]
        return candidates.filter { (try? $0.makeRenderer()) != nil }
    }()


    private struct Marker {
        let point: Point2D
        let color: (r: Double, g: Double, b: Double)
    }

    /// A synthetic "face": coloured discs at known coordinates on a black field.
    ///
    /// The eyes are deliberately different colours, and there is an off-centre white
    /// marker, so a horizontal mirror cannot pass unnoticed.
    private let leftEye = Marker(point: Point2D(300, 400), color: (1, 0, 0))     // red
    private let rightEye = Marker(point: Point2D(700, 400), color: (0, 1, 0))    // green
    private let mouth = Marker(point: Point2D(500, 850), color: (0, 0, 1))       // blue
    private let asymmetry = Marker(point: Point2D(250, 330), color: (1, 1, 0))   // yellow, upper left

    private let sourceSide = 1200

    private func makeSource() throws -> CGImage {
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try #require(CGContext(
            data: nil, width: sourceSide, height: sourceSide,
            bitsPerComponent: 8, bytesPerRow: 0, space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(red: 0, green: 0, blue: 0, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: sourceSide, height: sourceSide))

        // Draw in top-left, y-down space to match how the landmarks are expressed.
        context.translateBy(x: 0, y: Double(sourceSide))
        context.scaleBy(x: 1, y: -1)

        for marker in [leftEye, rightEye, mouth, asymmetry] {
            context.setFillColor(red: marker.color.r, green: marker.color.g, blue: marker.color.b, alpha: 1)
            let radius = 30.0
            context.fillEllipse(in: CGRect(
                x: marker.point.x - radius, y: marker.point.y - radius,
                width: radius * 2, height: radius * 2
            ))
        }
        return try #require(context.makeImage())
    }

    /// Reads `image` back as 8-bit sRGB so individual pixels can be inspected.
    private func pixels(of image: CGImage) throws -> (data: [UInt8], width: Int) {
        let width = image.width
        let height = image.height
        var data = [UInt8](repeating: 0, count: width * height * 4)
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        try data.withUnsafeMutableBytes { buffer in
            let context = try #require(CGContext(
                data: buffer.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ))
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        return (data, width)
    }

    /// Colour at a top-left-origin canvas coordinate. Returns nil off-canvas rather
    /// than trapping, so a mis-placed probe reports as a failed expectation.
    private func color(_ pixels: (data: [UInt8], width: Int), at point: Point2D) -> (r: Int, g: Int, b: Int, a: Int)? {
        let x = Int(point.x.rounded())
        let y = Int(point.y.rounded())
        let height = pixels.data.count / (pixels.width * 4)
        guard x >= 0, y >= 0, x < pixels.width, y < height else { return nil }
        let offset = (y * pixels.width + x) * 4
        return (Int(pixels.data[offset]), Int(pixels.data[offset + 1]),
                Int(pixels.data[offset + 2]), Int(pixels.data[offset + 3]))
    }

    @Test("each landmark's pixels land on its target coordinate", arguments: renderers)
    func landmarksLandOnTargets(resampler: Resampler) throws {
        let spec = CanvasSpec.standard
        let landmarks = FaceLandmarks(
            viewerLeftEye: leftEye.point,
            viewerRightEye: rightEye.point,
            mouth: mouth.point
        )
        // The synthetic face is built at exactly 1.125, so nothing should clamp.
        let alignment = try AlignmentSolver.solve(landmarks: landmarks, spec: spec)
        #expect(!alignment.stretchWasClamped)
        #expect(alignment.mouthResidual.length < 1e-6)

        let tile = try resampler.makeRenderer(spec: spec).render(makeSource(), using: alignment.transform)
        #expect(tile.width == 2048 && tile.height == 2048)

        let read = try pixels(of: tile)

        let atLeftEye = try #require(color(read, at: spec.viewerLeftEye))
        #expect(atLeftEye.r > 200 && atLeftEye.g < 60 && atLeftEye.b < 60,
                "\(resampler.rawValue): expected red at the left-eye target, got \(atLeftEye)")

        let atRightEye = try #require(color(read, at: spec.viewerRightEye))
        #expect(atRightEye.g > 200 && atRightEye.r < 60 && atRightEye.b < 60,
                "\(resampler.rawValue): expected green at the right-eye target, got \(atRightEye)")

        let atMouth = try #require(color(read, at: spec.mouth))
        #expect(atMouth.b > 200 && atMouth.r < 60 && atMouth.g < 60,
                "\(resampler.rawValue): expected blue at the mouth target, got \(atMouth)")
    }

    @Test("the output is neither mirrored nor flipped", arguments: renderers)
    func orientationIsPreserved(resampler: Resampler) throws {
        let spec = CanvasSpec.standard
        let landmarks = FaceLandmarks(
            viewerLeftEye: leftEye.point,
            viewerRightEye: rightEye.point,
            mouth: mouth.point
        )
        let alignment = try AlignmentSolver.solve(landmarks: landmarks, spec: spec)
        let tile = try resampler.makeRenderer(spec: spec).render(makeSource(), using: alignment.transform)
        let read = try pixels(of: tile)

        // The yellow marker sits above and to the left of the left eye in the source,
        // so it must still sit above and to the left in the canvas.
        let expected = alignment.transform.apply(to: asymmetry.point)
        #expect(expected.x < spec.viewerLeftEye.x, "asymmetry marker should stay left of the left eye")
        #expect(expected.y < spec.eyeLineY, "asymmetry marker should stay above the eye line")

        let atMarker = try #require(color(read, at: expected), "marker mapped off-canvas to \(expected)")
        #expect(atMarker.r > 200 && atMarker.g > 200 && atMarker.b < 60,
                "\(resampler.rawValue): expected yellow at the asymmetry marker, got \(atMarker)")
    }

    @Test("area outside the source stays transparent rather than being invented", arguments: renderers)
    func uncoveredAreaIsTransparent(resampler: Resampler) throws {
        let spec = CanvasSpec.standard
        // A face filling almost the whole frame: the canvas will overhang the source.
        let landmarks = FaceLandmarks(
            viewerLeftEye: Point2D(150, 300),
            viewerRightEye: Point2D(1050, 300),
            mouth: Point2D(600, 1312.5)
        )
        let alignment = try AlignmentSolver.solve(landmarks: landmarks, spec: spec)
        let fit = SourceFit.evaluate(
            alignment: alignment,
            sourceWidth: Double(sourceSide), sourceHeight: Double(sourceSide),
            spec: spec
        )
        #expect(!fit.isFullyCovered)

        let tile = try resampler.makeRenderer(spec: spec).render(makeSource(), using: alignment.transform)
        let read = try pixels(of: tile)
        #expect(try #require(color(read, at: Point2D(4, 4))).a == 0, "\(resampler.rawValue): the top-left corner should be empty")
    }

    @Test("the overlay renders without disturbing the tile's dimensions")
    func overlayRenders() throws {
        let spec = CanvasSpec.standard
        let landmarks = FaceLandmarks(
            viewerLeftEye: leftEye.point, viewerRightEye: rightEye.point, mouth: mouth.point
        )
        let alignment = try AlignmentSolver.solve(landmarks: landmarks, spec: spec)
        let tile = try CoreGraphicsRenderer(spec: spec).render(makeSource(), using: alignment.transform)
        let overlaid = try #require(OverlayRenderer(spec: spec).draw(over: tile))
        #expect(overlaid.width == 2048 && overlaid.height == 2048)
    }
}
