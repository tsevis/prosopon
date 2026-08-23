import CoreGraphics
import Foundation
import ProsoponCore
import ProsoponIO
import Testing
@testable import ProsoponInsight

/// Ground truth produced by the reference Python implementation on the same image.
struct Truth: Decodable {
    struct Face: Decodable {
        var bbox: [Double]
        var score: Double
        var kps: [[Double]]
        var lm106: [[Double]]
    }
    var width: Int
    var height: Int
    var faces: [Face]
}

@Suite("InsightFace parity")
struct ParityTests {
    static let fixtures = URL(fileURLWithPath: "/private/tmp/claude-501/-Users-tsevis-AI-ClaudeCode/acf95f85-4c9b-4d65-9e0c-723cbe28353b/scratchpad")

    static var available: Bool {
        FileManager.default.fileExists(atPath: fixtures.appendingPathComponent("t1.jpg").path)
            && ((try? ModelBundle.locate()) != nil)
    }

    private func load() throws -> (CGImage, Truth) {
        let image = try ImageLoading.load(Self.fixtures.appendingPathComponent("t1.jpg"))
        let truth = try JSONDecoder().decode(
            Truth.self,
            from: Data(contentsOf: Self.fixtures.appendingPathComponent("insightface_truth.json"))
        )
        return (image, truth)
    }

    @Test("the Swift detector finds the same faces as the reference", .enabled(if: available))
    func detectionParity() throws {
        let (image, truth) = try load()
        let detector = SCRFD(model: try ONNXModel(path: try ModelBundle.locate().detector))
        let found = try detector.detect(in: image).sorted { $0.box.x < $1.box.x }

        print("PARITY faces swift=\(found.count) python=\(truth.faces.count)")
        #expect(found.count == truth.faces.count)

        var worstCorner = 0.0
        var worstKeypoint = 0.0
        for (mine, reference) in zip(found, truth.faces) {
            worstCorner = max(worstCorner, abs(mine.box.x - reference.bbox[0]))
            worstCorner = max(worstCorner, abs(mine.box.y - reference.bbox[1]))
            worstCorner = max(worstCorner, abs(mine.box.x + mine.box.width - reference.bbox[2]))
            worstCorner = max(worstCorner, abs(mine.box.y + mine.box.height - reference.bbox[3]))
            for (point, expected) in zip(mine.keypoints, reference.kps) {
                worstKeypoint = max(worstKeypoint, point.distance(to: Point2D(expected[0], expected[1])))
            }
        }
        print("PARITY worst box corner \(String(format: "%.2f", worstCorner)) px, worst keypoint \(String(format: "%.2f", worstKeypoint)) px")
        // Measured at 1.6 px on a 1280 px image. The residue is resampling: Core Graphics
        // and OpenCV do not agree to the last bit when reducing an image by half.
        #expect(worstCorner < 4, "worst box corner \(worstCorner) px")
        #expect(worstKeypoint < 4, "worst keypoint \(worstKeypoint) px")
    }

    @Test("the 106 landmarks match the reference", .enabled(if: available))
    func landmarkParity() throws {
        let (image, truth) = try load()
        let bundle = try ModelBundle.locate()
        let detector = SCRFD(model: try ONNXModel(path: bundle.detector))
        let stage = Landmark106(model: try ONNXModel(path: bundle.landmarks))
        let found = try detector.detect(in: image).sorted { $0.box.x < $1.box.x }

        var worst = 0.0
        var total = 0.0
        var count = 0
        for (mine, reference) in zip(found, truth.faces) {
            let points = try stage.points(in: image, box: mine.box)
            #expect(points.count == 106)
            let interocular = Point2D(reference.kps[0][0], reference.kps[0][1])
                .distance(to: Point2D(reference.kps[1][0], reference.kps[1][1]))
            for (point, expected) in zip(points, reference.lm106) {
                let delta = point.distance(to: Point2D(expected[0], expected[1])) / interocular
                worst = max(worst, delta)
                total += delta
                count += 1
            }
        }
        print("PARITY 106 landmarks worst \(String(format: "%.4f", worst)) interocular, mean \(String(format: "%.4f", total / Double(count)))")
        // Measured: mean 0.004 of an interocular distance across all 106 points.
        #expect(total / Double(count) < 0.01, "mean \(total / Double(count)) interocular")
    }
}

extension ParityTests {
    /// The six points the project actually uses, and what disagreement on them costs
    /// once the face has been scaled up onto the 2048 canvas.
    @Test("the three canonical landmarks agree with the reference", .enabled(if: ParityTests.available))
    func canonicalLandmarkParity() throws {
        let image = try ImageLoading.load(Self.fixtures.appendingPathComponent("t1.jpg"))
        let truth = try JSONDecoder().decode(
            Truth.self,
            from: Data(contentsOf: Self.fixtures.appendingPathComponent("insightface_truth.json"))
        )
        let bundle = try ModelBundle.locate()
        let detector = SCRFD(model: try ONNXModel(path: bundle.detector))
        let stage = Landmark106(model: try ONNXModel(path: bundle.landmarks))
        let found = try detector.detect(in: image).sorted { $0.box.x < $1.box.x }

        var worstCanvas = 0.0
        for (mine, reference) in zip(found, truth.faces) {
            let points = try stage.points(in: image, box: mine.box)
            let swiftMarks = try #require(Landmark106.canonicalLandmarks(from: points))
            let pythonMarks = try #require(Landmark106.canonicalLandmarks(
                from: reference.lm106.map { Point2D($0[0], $0[1]) }
            ))

            // Scale the disagreement by how much this face gets enlarged to reach the
            // canvas, which is what turns a sub-pixel difference into a visible one.
            let magnification = CanvasSpec.standard.interocularDistance / swiftMarks.interocularDistance
            for landmark in Landmark.allCases {
                let delta = landmark.point(in: swiftMarks)
                    .distance(to: landmark.point(in: pythonMarks)) * magnification
                worstCanvas = max(worstCanvas, delta)
            }
        }
        print("PARITY canonical landmarks worst \(String(format: "%.2f", worstCanvas)) canvas px")
        // Every face in this fixture has an interocular distance between 29 and 51 px,
        // so reaching the canvas magnifies them 20 to 35 times -- far past the 2x the
        // pipeline accepts, and any disagreement with it. The median is 3.9 canvas px;
        // the bound is set for the smallest face, which no real run would keep.
        #expect(worstCanvas < 20, "worst \(worstCanvas) canvas px")
    }
}
