import CoreGraphics
import Foundation
import ProsoponCore
import ProsoponIO
import ProsoponQA
import Testing
@testable import ProsoponReview

/// Builds an on-disk align run for the session to open.
enum Fixture {
    static let canvas = 256.0

    /// Landmarks whose interocular distance keeps magnification inside the default gate.
    static func landmarks(offsetBy offset: Point2D = .zero) -> FaceLandmarks {
        FaceLandmarks(
            viewerLeftEye: Point2D(300, 400) + offset,
            viewerRightEye: Point2D(500, 400) + offset,
            mouth: Point2D(400, 625) + offset
        )
    }

    static func makeRun(
        names: [String],
        offsets: [Point2D]? = nil,
        writeTiles: Bool = true,
        qaDisplacements: [String: (Double, Double)]? = nil
    ) throws -> URL {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("prosopon-review-\(UInt64.random(in: 0...UInt64.max))")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        var records: [TileRecord] = []
        for (index, name) in names.enumerated() {
            let sourceURL = directory.appendingPathComponent("\(name)-source.png")
            try ImageWriting.write(try sourceImage(), to: sourceURL, format: .png)

            let marks = landmarks(offsetBy: offsets?[index] ?? .zero)
            let spec = CanvasSpec.standard.scaled(toSize: canvas)
            let alignment = try AlignmentSolver.solve(landmarks: marks, spec: spec)

            var outputPath: String?
            if writeTiles {
                let tileURL = directory.appendingPathComponent("\(name).png")
                try ImageWriting.write(try sourceImage(side: Int(canvas)), to: tileURL, format: .png)
                outputPath = tileURL.path
            }

            records.append(TileRecord(
                sourcePath: sourceURL.path, sourceWidth: 900, sourceHeight: 900,
                faceIndex: 0, outputPath: outputPath, accepted: true,
                landmarks: marks, transform: alignment.transform
            ))
        }

        let manifest = RunManifest(
            canvasSize: canvas, gridStep: canvas / 16,
            targets: [:], maxStretch: 0.05, maxShear: 0.05,
            detector: "vision", resampler: "coregraphics", tiles: records
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(manifest).write(to: directory.appendingPathComponent("manifest.json"))

        if let qaDisplacements {
            try writeQAReport(qaDisplacements, to: directory)
        }
        return directory
    }

    /// Written with the very encoder the QA pass uses.
    ///
    /// Hand-rolling this JSON is what hid the encoding bug: the fixture was written in
    /// the shape the reader wanted rather than the shape the writer produced, so the
    /// test passed while the real file was unreadable.
    private static func writeQAReport(_ values: [String: (Double, Double)], to directory: URL) throws {
        let report = StackQA(
            tileCount: values.count,
            canvasSize: canvas,
            landmarkSharpness: [:],
            globalSharpness: SharpnessRetention(
                meanImageAcutance: 1, averageTileAcutance: 1, retention: 1
            ),
            tiles: values.map { name, value in
                TileQA(name: name, path: "/tmp/\(name).png", offsets: [
                    .viewerLeftEye: ConsensusOffset(
                        dx: value.0, dy: 0, correlation: value.1, clipped: false
                    ),
                ])
            }
        )
        try JSONEncoder().encode(report)
            .write(to: directory.appendingPathComponent("qa.json"))
    }

    static func sourceImage(side: Int = 900) throws -> CGImage {
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try #require(CGContext(
            data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
            space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(red: 0.4, green: 0.35, blue: 0.3, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: side, height: side))
        for step in stride(from: 0, to: side, by: 17) {
            context.setFillColor(red: 0.9, green: 0.5, blue: 0.2, alpha: 1)
            context.fill(CGRect(x: step, y: (step * 3) % side, width: 6, height: 6))
        }
        return try #require(context.makeImage())
    }
}

@MainActor
@Suite("Review session")
struct ReviewSessionTests {

    @Test("a run is opened and every tile solved")
    func opensARun() throws {
        let directory = try Fixture.makeRun(names: ["a", "b", "c"])
        defer { try? FileManager.default.removeItem(at: directory) }

        let session = try ReviewSession(directory: directory)
        #expect(session.entries.count == 3)
        #expect(session.spec.size == Fixture.canvas)
        #expect(session.selection != nil)
        #expect(session.entries.allSatisfy { $0.alignment != nil })
    }

    @Test("a folder with no manifest says so plainly")
    func missingManifest() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("prosopon-empty-\(UInt64.random(in: 0...UInt64.max))")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        #expect(throws: ReviewLoadError.self) { try ReviewSession(directory: directory) }
    }

    @Test("the arrow keys walk the queue and stop at both ends")
    func navigation() throws {
        let directory = try Fixture.makeRun(names: ["a", "b", "c"])
        defer { try? FileManager.default.removeItem(at: directory) }

        let session = try ReviewSession(directory: directory)
        session.sortOrder = .name
        session.selection = session.entries[0].id

        session.selectNext()
        #expect(session.selectedIndex == 1)
        session.selectNext()
        session.selectNext()
        #expect(session.selectedIndex == 2, "stops at the end rather than wrapping")
        session.selectPrevious()
        #expect(session.selectedIndex == 1)
        session.selectPrevious()
        session.selectPrevious()
        #expect(session.selectedIndex == 0)
    }

    @Test("sorting by name is alphabetical")
    func sortByName() throws {
        let directory = try Fixture.makeRun(names: ["charlie", "alpha", "bravo"])
        defer { try? FileManager.default.removeItem(at: directory) }

        let session = try ReviewSession(directory: directory)
        session.sortOrder = .name
        #expect(session.entries.map(\.name) == ["alpha-source", "bravo-source", "charlie-source"])
    }

    @Test("a QA report drives the ordering when one is present")
    func consensusOrdering() throws {
        let directory = try Fixture.makeRun(
            names: ["quiet", "adrift", "unmatched"],
            qaDisplacements: ["quiet": (0.2, 0.99), "adrift": (6.0, 0.98), "unmatched": (1.0, 0.30)]
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let session = try ReviewSession(directory: directory)
        session.sortOrder = .consensus
        // Unmatched first: it needs a decision rather than a measurement. The QA report
        // is keyed on the tile filename, while `name` comes from the source file.
        #expect(session.entries[0].name == "unmatched-source")
        #expect(session.entries[1].name == "adrift-source")
        #expect(session.entries[2].name == "quiet-source")
        #expect(session.entries[1].consensusDisplacement.map { abs($0 - 6) < 1e-9 } == true)
        #expect(session.loadedQAReport, "the report the QA pass writes must actually decode")
    }

    @Test("a malformed QA report is reported rather than passed over in silence")
    func malformedQAReportIsSurfaced() throws {
        let directory = try Fixture.makeRun(names: ["a"])
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("{ not json at all".utf8)
            .write(to: directory.appendingPathComponent("qa.json"))

        let session = try ReviewSession(directory: directory)
        #expect(session.entries.count == 1, "the run still opens")
        #expect(session.loadedQAReport == false)
        #expect(session.qaReportProblem != nil, "a broken report must not fail quietly")
    }

    @Test("a missing QA report is simply not used")
    func absentQAReportIsFine() throws {
        let directory = try Fixture.makeRun(names: ["a", "b"])
        defer { try? FileManager.default.removeItem(at: directory) }

        let session = try ReviewSession(directory: directory)
        #expect(session.entries.allSatisfy { $0.consensusDisplacement == nil })
        #expect(session.loadedQAReport == false)
        #expect(session.qaReportProblem == nil, "absence is not a problem worth reporting")
    }

    @Test("a manifest from an older build still opens")
    func olderManifestIsTolerated() throws {
        // Written before `resampler` existed. Refusing the whole run over one missing
        // string would be a poor way to treat work done months ago.
        let directory = try Fixture.makeRun(names: ["a"])
        defer { try? FileManager.default.removeItem(at: directory) }

        let url = directory.appendingPathComponent("manifest.json")
        var json = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
        json.removeValue(forKey: "resampler")
        json.removeValue(forKey: "detector")
        try JSONSerialization.data(withJSONObject: json).write(to: url)

        let session = try ReviewSession(directory: directory)
        #expect(session.entries.count == 1)
        #expect(session.resampler == "lanczos", "a sensible default rather than a failure")
    }

    @Test("edits are counted, and reverting clears them")
    func editTracking() throws {
        let directory = try Fixture.makeRun(names: ["a", "b"])
        defer { try? FileManager.default.removeItem(at: directory) }

        let session = try ReviewSession(directory: directory)
        #expect(session.editCount == 0)

        session.moveLandmark(.viewerLeftEye, toCanvasPoint: Point2D(70, 70))
        #expect(session.editCount == 1)
        #expect(session.selected?.isEdited == true)

        session.revertSelected()
        #expect(session.editCount == 0)
    }

    @Test("a prospective solve reports the outcome without committing it")
    func prospectiveSolveDoesNotCommit() throws {
        let directory = try Fixture.makeRun(names: ["a"])
        defer { try? FileManager.default.removeItem(at: directory) }

        let session = try ReviewSession(directory: directory)
        let before = session.selected?.landmarks

        let probe = session.prospectiveEntry(.mouth, atCanvasPoint: Point2D(120, 200))
        #expect(probe != nil)
        #expect(probe?.isEdited == true)
        #expect(session.selected?.landmarks == before, "the session must be untouched")
        #expect(session.editCount == 0)
    }

    @Test("revert all restores every tile at once")
    func revertAll() throws {
        let directory = try Fixture.makeRun(names: ["a", "b", "c"])
        defer { try? FileManager.default.removeItem(at: directory) }

        let session = try ReviewSession(directory: directory)
        for entry in session.entries {
            session.selection = entry.id
            session.moveLandmark(.mouth, toCanvasPoint: Point2D(130, 210))
        }
        #expect(session.editCount == 3)
        session.revertAll()
        #expect(session.editCount == 0)
    }
}
