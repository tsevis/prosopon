import CoreGraphics
import Foundation
import ProsoponCore
import Testing
@testable import ProsoponInsight

/// The parts that need no model on disk.
@Suite("Insight geometry")
struct GeometryTests {

    @Test("the crop transform centres the box in the model's square")
    func cropTransformCentresTheBox() {
        let box = BoundingBox(x: 100, y: 200, width: 80, height: 120)
        let transform = Landmark106.cropTransform(for: box)

        let centre = transform.apply(to: box.center)
        #expect(abs(centre.x - 96) < 1e-9, "the box centre belongs at the crop centre")
        #expect(abs(centre.y - 96) < 1e-9)

        // The longer side gets half again as much room, so 120 px of face becomes 180 of 192.
        #expect(abs(transform.a - 192.0 / 180.0) < 1e-9)
        #expect(transform.a == transform.d, "the crop is not allowed to distort the face")
        #expect(transform.b == 0 && transform.c == 0)
    }

    @Test("a wide box is squared off by its longer side")
    func cropUsesTheLongerSide() {
        let wide = Landmark106.cropTransform(for: BoundingBox(x: 0, y: 0, width: 200, height: 50))
        let tall = Landmark106.cropTransform(for: BoundingBox(x: 0, y: 0, width: 50, height: 200))
        #expect(abs(wide.a - tall.a) < 1e-9, "both are governed by their 200 px side")
    }

    @Test("the canonical landmarks come from the established indices")
    func canonicalIndicesAreUsed() throws {
        var points = (0..<106).map { Point2D(Double($0), 1000) }
        // An upright face: eyes level, mouth below.
        points[Landmark106.Index.leftEyeOuterCanthus] = Point2D(100, 200)
        points[Landmark106.Index.leftEyeInnerCanthus] = Point2D(140, 200)
        points[Landmark106.Index.rightEyeOuterCanthus] = Point2D(300, 200)
        points[Landmark106.Index.rightEyeInnerCanthus] = Point2D(260, 200)
        points[Landmark106.Index.leftMouthCommissure] = Point2D(150, 400)
        points[Landmark106.Index.rightMouthCommissure] = Point2D(250, 400)

        let landmarks = try #require(Landmark106.canonicalLandmarks(from: points))
        #expect(landmarks.viewerLeftEye == Point2D(120, 200), "midpoint of the two canthi")
        #expect(landmarks.viewerRightEye == Point2D(280, 200))
        #expect(landmarks.mouth == Point2D(200, 400), "midpoint of the two commissures")
    }

    @Test("which eye is on the viewer's left is decided by geometry, not by index")
    func viewerOrderingIsGeometric() throws {
        // An upside-down face: the index named "left" now appears on the right, and the
        // ordering has to follow what is on screen rather than what the model calls it.
        var points = (0..<106).map { _ in Point2D(0, 0) }
        points[Landmark106.Index.leftEyeOuterCanthus] = Point2D(300, 400)
        points[Landmark106.Index.leftEyeInnerCanthus] = Point2D(260, 400)
        points[Landmark106.Index.rightEyeOuterCanthus] = Point2D(100, 400)
        points[Landmark106.Index.rightEyeInnerCanthus] = Point2D(140, 400)
        points[Landmark106.Index.leftMouthCommissure] = Point2D(250, 600)
        points[Landmark106.Index.rightMouthCommissure] = Point2D(150, 600)

        let landmarks = try #require(Landmark106.canonicalLandmarks(from: points))
        #expect(landmarks.viewerLeftEye.x < landmarks.viewerRightEye.x)
    }

    @Test("a short point list is refused rather than read past its end")
    func shortListIsRefused() {
        #expect(Landmark106.canonicalLandmarks(from: [Point2D(0, 0)]) == nil)
        #expect(Landmark106.canonicalLandmarks(from: []) == nil)
    }

    @Test("a missing model directory says where it looked")
    func missingModelsAreReported() {
        #expect(throws: InsightError.self) {
            try ModelBundle.locate(explicit: "/nonexistent/models")
        }
        do {
            _ = try ModelBundle.locate(explicit: "/nonexistent/models")
        } catch {
            #expect("\(error)".contains("/nonexistent/models"))
            #expect("\(error)".contains("det_10g.onnx"))
        }
    }

    @Test("the letterbox fits the whole photograph into the square")
    func letterboxFits() {
        let transform = ImageTensor.letterbox(imageWidth: 1280, imageHeight: 720, side: 640)
        #expect(abs(transform.a - 0.5) < 1e-9, "the wider side governs")
        #expect(transform.tx == 0 && transform.ty == 0, "unpadded, the image sits top-left")
        let corner = transform.apply(to: Point2D(1280, 720))
        #expect(abs(corner.x - 640) < 1e-9)
        #expect(corner.y <= 640, "the shorter side leaves the rest of the square empty")
    }

    @Test("a margin insets the photograph and still fits it")
    func letterboxWithMargin() throws {
        // SCRFD cannot see a face that fills its frame, so the retry puts space around it.
        let transform = ImageTensor.letterbox(
            imageWidth: 1000, imageHeight: 1000, side: 640, margin: 0.5
        )
        // 1000 px inset by 500 on each side is a 2000 px canvas mapped onto 640.
        #expect(abs(transform.a - 0.32) < 1e-9)
        #expect(abs(transform.tx - 160) < 1e-9, "the inset is carried in the translation")

        for corner in [Point2D(0, 0), Point2D(1000, 1000)] {
            let mapped = transform.apply(to: corner)
            #expect(mapped.x >= 0 && mapped.x <= 640)
            #expect(mapped.y >= 0 && mapped.y <= 640)
        }
        // Detections come back through the inverse, so it has to undo both parts.
        let inverse = try #require(transform.inverted)
        let round = inverse.apply(to: transform.apply(to: Point2D(321, 654)))
        #expect(abs(round.x - 321) < 1e-9 && abs(round.y - 654) < 1e-9)
    }
}
