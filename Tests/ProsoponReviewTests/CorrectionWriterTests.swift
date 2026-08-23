import Foundation
import ProsoponCore
import ProsoponRender
import Testing
@testable import ProsoponReview

@MainActor
@Suite("Correction writer")
struct CorrectionWriterTests {

    private func save(_ session: ReviewSession) throws -> CorrectionWriter.Summary {
        try CorrectionWriter.save(
            entries: session.entries, directory: session.directory,
            spec: session.spec, options: session.options, resampler: .coreGraphics
        )
    }

    private func manifest(at directory: URL) throws -> RunManifest {
        try JSONDecoder().decode(
            RunManifest.self,
            from: Data(contentsOf: directory.appendingPathComponent("manifest.json"))
        )
    }

    @Test("saving with nothing edited writes nothing")
    func noEditsNoWrites() throws {
        let directory = try Fixture.makeRun(names: ["a", "b"])
        defer { try? FileManager.default.removeItem(at: directory) }

        let session = try ReviewSession(directory: directory)
        let before = try Data(contentsOf: directory.appendingPathComponent("a.png"))
        let summary = try save(session)

        #expect(summary.rewritten == 0)
        #expect(try Data(contentsOf: directory.appendingPathComponent("a.png")) == before)
    }

    @Test("only the edited tile is rewritten")
    func onlyEditedTilesAreRewritten() throws {
        let directory = try Fixture.makeRun(names: ["a", "b", "c"])
        defer { try? FileManager.default.removeItem(at: directory) }

        let session = try ReviewSession(directory: directory)
        session.sortOrder = .name
        session.selection = session.entries[1].id
        session.moveLandmark(.viewerLeftEye, toCanvasPoint: Point2D(70, 66))

        let untouchedBefore = try Data(contentsOf: directory.appendingPathComponent("a.png"))
        let summary = try save(session)

        #expect(summary.rewritten == 1)
        #expect(summary.failures.isEmpty)
        // Saving one correction out of three must not rewrite the other two.
        #expect(try Data(contentsOf: directory.appendingPathComponent("a.png")) == untouchedBefore)
    }

    @Test("the corrected landmarks and transform reach the manifest")
    func manifestIsUpdated() throws {
        let directory = try Fixture.makeRun(names: ["a"])
        defer { try? FileManager.default.removeItem(at: directory) }

        let session = try ReviewSession(directory: directory)
        let original = try manifest(at: directory).tiles[0]
        session.moveLandmark(.mouth, toCanvasPoint: Point2D(130, 220))
        let corrected = session.selected!

        _ = try save(session)
        let updated = try manifest(at: directory).tiles[0]

        #expect(updated.landmarks == corrected.landmarks)
        #expect(updated.landmarks != original.landmarks)
        #expect(updated.transform == corrected.alignment?.transform)
        #expect(updated.nativeMouthDropRatio != original.nativeMouthDropRatio)
    }

    @Test("a correction that fails the gates removes the tile and clears its path")
    func rejectedCorrectionRemovesTheTile() throws {
        // A correction can push a tile out of the stack as well as into it, and leaving
        // a stale file behind would put an unusable tile into the next stack run.
        let directory = try Fixture.makeRun(names: ["a"])
        defer { try? FileManager.default.removeItem(at: directory) }

        let session = try ReviewSession(directory: directory)
        // Dragging the left eye almost onto the right one leaves a tiny interocular
        // distance, so the tile would have to be enlarged far past the gate. It still
        // solves -- this is a rejection, not a failure.
        session.moveLandmark(.viewerLeftEye, toCanvasPoint: Point2D(170, 64))
        #expect(session.selected?.alignment != nil, "it must still solve")
        #expect(session.selected?.quality?.isAccepted == false)
        #expect(session.selected?.quality?.rejections.contains(.excessiveMagnification) == true)

        let summary = try save(session)
        #expect(summary.nowRejected == 1)
        #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("a.png").path))
        #expect(try manifest(at: directory).tiles[0].outputPath == nil)
        #expect(try manifest(at: directory).tiles[0].accepted == false)
    }

    @Test("saving twice is stable")
    func savingIsIdempotent() throws {
        let directory = try Fixture.makeRun(names: ["a"])
        defer { try? FileManager.default.removeItem(at: directory) }

        let session = try ReviewSession(directory: directory)
        session.moveLandmark(.mouth, toCanvasPoint: Point2D(128, 215))
        _ = try save(session)
        let first = try Data(contentsOf: directory.appendingPathComponent("a.png"))
        _ = try save(session)
        #expect(try Data(contentsOf: directory.appendingPathComponent("a.png")) == first)
    }

    @Test("a reopened run carries the corrections")
    func correctionsSurviveReopening() throws {
        let directory = try Fixture.makeRun(names: ["a", "b"])
        defer { try? FileManager.default.removeItem(at: directory) }

        let session = try ReviewSession(directory: directory)
        session.sortOrder = .name
        session.selection = session.entries[0].id
        session.moveLandmark(.mouth, toCanvasPoint: Point2D(126, 212))
        let corrected = session.selected!.landmarks
        _ = try save(session)

        let reopened = try ReviewSession(directory: directory)
        reopened.sortOrder = .name
        #expect(reopened.entries[0].landmarks == corrected)
        // Reopened, the correction is the new baseline rather than a pending edit.
        #expect(reopened.editCount == 0)
    }
}
