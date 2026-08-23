import CoreGraphics
import Foundation
import ProsoponCore
import ProsoponIO
import ProsoponRender
import ProsoponVision
import Testing
@testable import ProsoponPipeline

/// A detector that answers from a table rather than from pixels, so the fan-out can be
/// tested without making the result depend on Vision agreeing with itself.
private struct ScriptedDetector: LandmarkDetector {
    let faces: [DetectedFace]
    var failsWith: String?

    var name: String { "scripted" }

    func detect(in image: CGImage) throws -> [DetectedFace] {
        if let failsWith { throw ScriptedFailure(message: failsWith) }
        return faces
    }
}

private struct ScriptedFailure: Error, CustomStringConvertible {
    let message: String
    var description: String { message }
}

private func face(at centre: Point2D = Point2D(400, 400), scale: Double = 1) -> DetectedFace {
    let marks = FaceLandmarks(
        viewerLeftEye: centre + Point2D(-150 * scale, -100 * scale),
        viewerRightEye: centre + Point2D(150 * scale, -100 * scale),
        mouth: centre + Point2D(0, 237.5 * scale)
    )
    return DetectedFace(
        landmarks: marks,
        boundingBox: BoundingBox(
            x: centre.x - 200 * scale, y: centre.y - 200 * scale,
            width: 400 * scale, height: 400 * scale
        ),
        confidence: 1
    )
}

@Suite("Batch runner")
struct BatchRunnerTests {

    private func makePipeline(
        detector: any LandmarkDetector,
        selection: FaceSelection = .all
    ) throws -> Pipeline {
        let spec = CanvasSpec.standard.scaled(toSize: 128)
        return Pipeline(
            spec: spec,
            solveOptions: .default,
            // Nothing here is about the gates, and a 900 px source cannot fill a 2048
            // canvas, so they are opened up to keep the subject of the test in view.
            thresholds: QualityThresholds(requiresFullCoverage: false, maxMagnification: .infinity),
            selection: selection,
            detector: detector,
            renderer: CoreGraphicsRenderer(spec: spec),
            output: nil
        )
    }

    /// 900 px square, because the pipeline reads the real dimensions and the face
    /// selection measures distance from the image's own centre. On an 8 px placeholder
    /// every face is equally far from the middle and `central` means nothing.
    private func makeImages(_ count: Int) throws -> (URL, [URL]) {
        let tree = try Tree()
        let urls = try (0..<count).map {
            try tree.image(String(format: "img-%03d.png", $0), side: 900)
        }
        return (tree.root, urls)
    }

    @Test("results come back in input order whatever order the work finished in")
    func resultsFollowTheInput() async throws {
        // The fan-out is unordered by construction, so the collection by index is the
        // only thing making a batch reproducible -- and a manifest whose rows shuffle
        // between identical runs is a manifest nobody can diff.
        let (root, urls) = try makeImages(24)
        defer { try? FileManager.default.removeItem(at: root) }

        let pipeline = try makePipeline(detector: ScriptedDetector(faces: [face()]))
        let records = await BatchRunner.run(urls: urls, pipeline: pipeline, concurrency: 8)

        #expect(records.count == urls.count)
        #expect(records.map(\.sourcePath) == urls.map(\.path))
    }

    @Test("progress counts every image exactly once and ends on the total")
    func progressIsComplete() async throws {
        let (root, urls) = try makeImages(12)
        defer { try? FileManager.default.removeItem(at: root) }

        let recorder = ProgressRecorder()
        let pipeline = try makePipeline(detector: ScriptedDetector(faces: [face()]))
        _ = await BatchRunner.run(
            urls: urls, pipeline: pipeline, concurrency: 4,
            onProgress: { recorder.record($0) }
        )

        let seen = recorder.completedValues
        #expect(seen.count == urls.count)
        #expect(Set(seen) == Set(1...urls.count), "every step reported once, none twice")
        #expect(recorder.last?.total == urls.count)
        #expect(recorder.last?.isFinished == true)
        #expect(recorder.last?.fraction == 1)
    }

    @Test("progress is optional, and a batch without it still runs")
    func progressIsOptional() async throws {
        // The CLI draws a bar and the app shows a bar; neither is the runner's business,
        // and a headless caller should not have to supply one.
        let (root, urls) = try makeImages(3)
        defer { try? FileManager.default.removeItem(at: root) }

        let pipeline = try makePipeline(detector: ScriptedDetector(faces: [face()]))
        let records = await BatchRunner.run(urls: urls, pipeline: pipeline, concurrency: 2)
        #expect(records.count == 3)
    }

    @Test("an empty batch finishes rather than reporting nothing at all")
    func emptyBatch() async throws {
        let pipeline = try makePipeline(detector: ScriptedDetector(faces: [face()]))
        let records = await BatchRunner.run(urls: [], pipeline: pipeline, concurrency: 4)
        #expect(records.isEmpty)
        #expect(BatchRunner.Progress(completed: 0, total: 0).fraction == 1)
    }

    @Test("a photograph the detector fails on does not take the batch with it")
    func oneFailureDoesNotStopTheRest() async throws {
        let (root, urls) = try makeImages(4)
        defer { try? FileManager.default.removeItem(at: root) }

        let pipeline = try makePipeline(
            detector: ScriptedDetector(faces: [], failsWith: "detector fell over")
        )
        let records = await BatchRunner.run(urls: urls, pipeline: pipeline, concurrency: 2)

        #expect(records.count == 4)
        #expect(records.allSatisfy { $0.failure != nil })
        #expect(records.allSatisfy { !$0.accepted })
    }

    @Test("a group photograph becomes one row per face, numbered in order")
    func everyFaceBecomesATile() async throws {
        let (root, urls) = try makeImages(1)
        defer { try? FileManager.default.removeItem(at: root) }

        let three = [face(at: Point2D(200, 300)), face(at: Point2D(450, 300)), face(at: Point2D(700, 300))]
        let pipeline = try makePipeline(detector: ScriptedDetector(faces: three))
        let records = await BatchRunner.run(urls: urls, pipeline: pipeline, concurrency: 1)

        #expect(records.count == 3)
        #expect(records.map(\.faceIndex) == [0, 1, 2])
    }

    @Test("largest and central each pick one face, and not the same one")
    func faceSelectionNarrows() async throws {
        let (root, urls) = try makeImages(1)
        defer { try? FileManager.default.removeItem(at: root) }

        // A 900 px source, so its centre is (450, 450): the big face sits well off in a
        // corner, the small one right on the middle.
        let big = face(at: Point2D(200, 250), scale: 1.5)
        let small = face(at: Point2D(450, 450), scale: 0.5)
        let detector = ScriptedDetector(faces: [big, small])

        let all = await BatchRunner.run(
            urls: urls, pipeline: try makePipeline(detector: detector, selection: .all), concurrency: 1
        )
        let largest = await BatchRunner.run(
            urls: urls, pipeline: try makePipeline(detector: detector, selection: .largest), concurrency: 1
        )
        let central = await BatchRunner.run(
            urls: urls, pipeline: try makePipeline(detector: detector, selection: .central), concurrency: 1
        )

        #expect(all.count == 2)
        #expect(largest.count == 1)
        #expect(central.count == 1)
        #expect(largest[0].landmarks == big.landmarks)
        #expect(central[0].landmarks == small.landmarks)
    }

    @Test("a photograph with no face in it says so, once")
    func noFaceIsOneRow() async throws {
        let (root, urls) = try makeImages(2)
        defer { try? FileManager.default.removeItem(at: root) }

        let pipeline = try makePipeline(detector: ScriptedDetector(faces: []))
        let records = await BatchRunner.run(urls: urls, pipeline: pipeline, concurrency: 2)

        #expect(records.count == 2)
        #expect(records.allSatisfy { $0.failure == "no face detected" })
    }

    @Test("a file that is not an image is reported against that file")
    func unreadableImage() async throws {
        let tree = try Tree(); defer { tree.remove() }
        let broken = try tree.file("broken.png", contents: "this is not a PNG")

        let pipeline = try makePipeline(detector: ScriptedDetector(faces: [face()]))
        let records = await BatchRunner.run(urls: [broken], pipeline: pipeline, concurrency: 1)

        #expect(records.count == 1)
        #expect(records[0].failure != nil)
        #expect(records[0].sourcePath == broken.path)
    }
}

/// Progress arrives from whichever task finished, so the callback needs somewhere
/// thread-safe to land.
private final class ProgressRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [BatchRunner.Progress] = []

    func record(_ progress: BatchRunner.Progress) {
        lock.lock(); defer { lock.unlock() }
        values.append(progress)
    }

    var completedValues: [Int] {
        lock.lock(); defer { lock.unlock() }
        return values.map(\.completed)
    }

    var last: BatchRunner.Progress? {
        lock.lock(); defer { lock.unlock() }
        return values.last
    }
}
