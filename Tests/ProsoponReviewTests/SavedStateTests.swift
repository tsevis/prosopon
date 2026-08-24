import CoreGraphics
import Foundation
import ImageIO
import ProsoponCore
import ProsoponIO
import ProsoponRender
import Testing
@testable import ProsoponReview

/// What the app knows about a run it did not make, and about what it has written.
///
/// Both of these went wrong at once on a real corpus and produced the same appearance —
/// a reviewer saving corrections over and over with nothing seeming to happen. Neither
/// was visible from inside the code: one was a gate re-applied at the wrong value, the
/// other a count that measured the wrong difference.
@MainActor
@Suite("Saved state and the run's gates")
struct SavedStateTests {

    /// An app state whose settings go to a throwaway suite.
    ///
    /// Not `.standard`: these tests write the very keys the running application reads, so
    /// one that used the real defaults would reach out of the test process and change the
    /// user's slider. It did, once, before this existed.
    private func app(directory: URL? = nil, defaults: UserDefaults? = nil) -> AppState {
        let suite = defaults ?? UserDefaults(
            suiteName: "com.tsevis.prosopon.tests.saved.\(UInt64.random(in: 0...UInt64.max))"
        )!
        return AppState(
            directory: directory, sources: SourceLibrary(restoring: false), defaults: suite
        )
    }

    // MARK: The gates travel with the run

    @Test("a run reopens under the gates it was made with, not the built-in ones")
    func thresholdsSurviveTheManifest() throws {
        // The failure this pins: seventeen of twenty tiles came back marked
        // `enlarged too far` on reopening, with their files sitting untouched beside the
        // manifest, because the app re-solved every one of them against the default 2.0.
        let raised = QualityThresholds(maxMagnification: 8)
        let directory = try Fixture.makeRun(
            names: ["small"], landmarks: Fixture.smallFaceLandmarks(), thresholds: raised
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let session = try ReviewSession(directory: directory)
        #expect(session.thresholds.maxMagnification == 8)

        let entry = try #require(session.entries.first)
        let magnification = try #require(entry.quality?.magnification)
        #expect(magnification > 2, "the fixture should need more enlargement than the default allows")
        #expect(entry.quality?.isAccepted == true, "accepted at 8x, as the run was")
        #expect(entry.quality?.rejections.isEmpty == true)
    }

    @Test("the same tile is declined when the run really was made at the default")
    func defaultThresholdsStillBite() throws {
        // The gate is not being disabled — it is being applied at the value that was used.
        let directory = try Fixture.makeRun(
            names: ["small"], landmarks: Fixture.smallFaceLandmarks()
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let entry = try #require(try ReviewSession(directory: directory).entries.first)
        #expect(entry.quality?.rejections == [.excessiveMagnification])
    }

    @Test("a manifest written before the gates travelled in it still opens")
    func olderManifestsStillOpen() throws {
        let directory = try Fixture.makeRun(names: ["a"])
        defer { try? FileManager.default.removeItem(at: directory) }

        // Strip the fields a newer writer adds, which is what an older run looks like.
        let url = directory.appendingPathComponent("manifest.json")
        var json = try #require(
            try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        )
        json.removeValue(forKey: "thresholds")
        json.removeValue(forKey: "bitDepth")
        try JSONSerialization.data(withJSONObject: json).write(to: url)

        let session = try ReviewSession(directory: directory)
        #expect(session.thresholds.maxMagnification == QualityThresholds.default.maxMagnification)
        #expect(session.bitDepth == 16)
        #expect(session.entries.count == 1)
    }

    @Test("opening a run sets the Analyze control to the gate that run used")
    func openingARunAdoptsItsThresholds() throws {
        // The gap this closes, and it undid a whole corpus: the manifest carried 3.5,
        // the review side honoured it, and the slider on Analyze still read 2.0 because
        // it was a stored default nothing ever touched. So Analyse Again re-ran twenty
        // portraits at 2.0 and threw seventeen of them away — the one control on that
        // screen silently reverting the setting the run was made with.
        let raised = QualityThresholds(maxMagnification: 3.5)
        let directory = try Fixture.makeRun(names: ["a"], thresholds: raised)
        defer { try? FileManager.default.removeItem(at: directory) }

        let app = app(directory: directory)
        app.openPending()

        #expect(app.maxMagnification == 3.5, "the slider shows what this run was made with")
    }

    @Test("a run made at the default leaves the control at the default")
    func openingAPlainRunDoesNotMoveTheControl() throws {
        let directory = try Fixture.makeRun(names: ["a"])
        defer { try? FileManager.default.removeItem(at: directory) }

        let app = app(directory: directory)
        app.openPending()

        #expect(app.maxMagnification == QualityThresholds.default.maxMagnification)
    }

    @Test("the gate survives quitting the app")
    func theGateIsRemembered() throws {
        // Why this is not a nicety: the control is the only thing standing between a
        // corpus and Analyse writing it away. A value that resets to the built-in
        // default every launch means the next launch destroys the run the last one
        // made — which is exactly what happened, twice, to the same twenty portraits.
        let suite = "com.tsevis.prosopon.tests.gate.\(UInt64.random(in: 0...UInt64.max))"
        let defaults = UserDefaults(suiteName: suite)!
        defer { UserDefaults().removePersistentDomain(forName: suite) }

        let first = app(defaults: defaults)
        first.maxMagnification = 3.5

        let second = app(defaults: defaults)
        #expect(second.maxMagnification == 3.5)
    }

    @Test("the gate follows the run already sitting in the output folder")
    func theGateFollowsTheRunAtTheOutput() throws {
        // Analysing into a folder that already holds a run is the ordinary case — it is
        // what Analyse Again does. The control has to describe that run, or pressing it
        // quietly re-makes it under different rules.
        let directory = try Fixture.makeRun(
            names: ["a"], thresholds: QualityThresholds(maxMagnification: 3.5)
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let app = app()
        #expect(app.maxMagnification == QualityThresholds.default.maxMagnification)

        app.outputDirectory = directory
        #expect(app.maxMagnification == 3.5, "the folder already says what it was made at")
    }

    @Test("pointing at an empty folder leaves the gate alone")
    func anEmptyOutputFolderChangesNothing() throws {
        let empty = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("prosopon-empty-\(UInt64.random(in: 0...UInt64.max))")
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: empty) }

        let app = app()
        app.maxMagnification = 4.0
        app.outputDirectory = empty
        #expect(app.maxMagnification == 4.0, "nothing there to take a value from")
    }

    // MARK: How far a face may be stretched

    @Test("opening a run sets the stretch control to what that run used")
    func openingARunAdoptsItsStretch() throws {
        // The gap this closes is the one the magnification slider had, in the setting
        // that decides whether the mouth lands on the seam at all. A run made at 12 per
        // cent reopened showing 5, and Analyse Again would have re-made it at 5 —
        // putting the mouth off target on sixty-four more tiles than it needed to be.
        let directory = try Fixture.makeRun(
            names: ["a"], solveOptions: SolveOptions(maxStretch: 0.12)
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let app = app(directory: directory)
        app.openPending()

        #expect(app.maxStretch == 0.12)
    }

    @Test("the stretch control follows the run already in the output folder")
    func stretchFollowsTheRunAtTheOutput() throws {
        // Analysing into a folder that already holds a run is what Analyse Again does.
        let directory = try Fixture.makeRun(
            names: ["a"], solveOptions: SolveOptions(maxStretch: 0.12)
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let app = app()
        #expect(app.maxStretch == SolveOptions.default.maxStretch)
        app.outputDirectory = directory
        #expect(app.maxStretch == 0.12)
    }

    @Test("the stretch setting survives quitting the app")
    func theStretchIsRemembered() throws {
        let suite = "com.tsevis.prosopon.tests.stretch.\(UInt64.random(in: 0...UInt64.max))"
        let defaults = UserDefaults(suiteName: suite)!
        defer { UserDefaults().removePersistentDomain(forName: suite) }

        let first = app(defaults: defaults)
        first.maxStretch = 0.12

        let second = app(defaults: defaults)
        #expect(second.maxStretch == 0.12)
    }

    @Test("what Analyse would run with is what the screen shows")
    func solveOptionsFollowTheControl() {
        // The whole point: the value on the slider is the value the run is made at.
        // Shear is left alone — it is the one linear operation that can slide a mouth
        // sideways with both eyes pinned, and it is not what this control is about.
        let app = app()
        app.maxStretch = 0.12

        #expect(app.solveOptions.maxStretch == 0.12)
        #expect(app.solveOptions.maxShear == SolveOptions.default.maxShear)
        #expect(app.solveOptions.correctsHorizontalMouthOffset)
    }

    @Test("the shear cap is a control too, adopted and remembered")
    func shearIsAControl() throws {
        // Stretch places the mouth on the y axis, shear on the x. Measured on 204
        // portraits: at 25% stretch with the default 5% shear the worst mouth still
        // finished 32.5 px off target, and every one of those pixels was horizontal.
        // Raising shear to 20% brought the worst to 0.0. A control for one without the
        // other cannot put a mouth where it belongs.
        let directory = try Fixture.makeRun(
            names: ["a"], solveOptions: SolveOptions(maxStretch: 0.25, maxShear: 0.2)
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let opened = app(directory: directory)
        opened.openPending()
        #expect(opened.maxShear == 0.2)

        let suite = UserDefaults(
            suiteName: "com.tsevis.prosopon.tests.shear.\(UInt64.random(in: 0...UInt64.max))"
        )!
        defer { UserDefaults().removePersistentDomain(forName: suite.description) }
        let first = app(defaults: suite)
        first.maxShear = 0.2
        #expect(app(defaults: suite).maxShear == 0.2, "and it survives quitting")
    }

    @Test("shear of zero turns the horizontal correction off, as the run writer records it")
    func zeroShearMeansNoHorizontalCorrection() {
        // `correctsHorizontalMouthOffset` is not a separate switch anywhere the user can
        // see; it is what a shear budget of nothing means. The session reads it back the
        // same way, so the two must agree.
        let app = app()
        app.maxShear = 0
        #expect(!app.solveOptions.correctsHorizontalMouthOffset)

        app.maxShear = 0.2
        #expect(app.solveOptions.correctsHorizontalMouthOffset)
        #expect(app.solveOptions.maxShear == 0.2)
    }

    // MARK: Knowing what has been written

    @Test("saving clears the count of unsaved corrections")
    func savingClearsTheEditCount() throws {
        // The bug: `isEdited` meant "differs from the detector", which stays true after a
        // correction is written. The banner claimed unsaved work for ever, Save stayed
        // lit, and pressing it again re-rendered the same tiles — a save that worked and
        // could not say so.
        let directory = try Fixture.makeRun(names: ["a", "b"])
        defer { try? FileManager.default.removeItem(at: directory) }

        let session = try ReviewSession(directory: directory)
        session.selection = session.entries.first?.id
        session.moveLandmark(.viewerLeftEye, toSourcePoint: Point2D(305, 402))

        #expect(session.editCount == 1)
        #expect(session.correctedCount == 1)

        let summary = try CorrectionWriter.save(
            entries: session.entries, directory: session.directory,
            spec: session.spec, options: session.options, resampler: .coreGraphics,
            depth: OutputDepth(rawValue: session.bitDepth) ?? .sixteen
        )
        session.markSaved(summary.written)

        #expect(session.editCount == 0, "the correction is on disk; nothing is outstanding")
        #expect(session.correctedCount == 1, "but it is still a correction, and Revert applies")
        #expect(summary.rewritten == 1)
    }

    @Test("Revert stays available after a save, and Save does not")
    func controlsFollowTheTwoCounts() {
        // Two different questions, and before this they were answered by one number.
        let saved = ChromeState(runName: "r", tileCount: 2, acceptedCount: 2,
                                editCount: 0, correctedCount: 1)
        let commands = CommandSet.commands(for: .fineTune, state: saved)
        #expect(commands.first { $0.action == .revertTile }?.isEnabled == true)
        #expect(commands.first { $0.action == .saveCorrections }?.isEnabled == false)
        #expect(StatusBanner.message(for: .fineTune, state: saved).kind == .notice)

        let unsaved = ChromeState(runName: "r", tileCount: 2, acceptedCount: 2,
                                  editCount: 1, correctedCount: 1)
        #expect(StatusBanner.message(for: .fineTune, state: unsaved).text.contains("not yet saved"))
    }

    @Test("a tile edited again while its save was in flight is not called saved")
    func editDuringSaveIsNotLost() throws {
        let directory = try Fixture.makeRun(names: ["a"])
        defer { try? FileManager.default.removeItem(at: directory) }

        let session = try ReviewSession(directory: directory)
        session.selection = session.entries.first?.id
        session.moveLandmark(.viewerLeftEye, toSourcePoint: Point2D(305, 402))
        let inFlight = try #require(session.entries.first?.landmarks)

        // The reviewer keeps working while the writer is busy with the earlier state.
        session.moveLandmark(.viewerLeftEye, toSourcePoint: Point2D(310, 404))
        session.markSaved([try #require(session.entries.first?.id): inFlight])

        #expect(session.editCount == 1, "the newer edit has not been written")
    }

    // MARK: Depth

    @Test("a correction re-renders at the depth the rest of the run is in")
    func correctionsKeepTheRunsDepth() throws {
        // An 8-bit run re-rendering one tile at 16 leaves a 24 MB file beside its 6 MB
        // neighbours, storing nothing the source ever carried.
        let directory = try Fixture.makeRun(names: ["a"], bitDepth: 8)
        defer { try? FileManager.default.removeItem(at: directory) }

        let session = try ReviewSession(directory: directory)
        #expect(session.bitDepth == 8)
        session.selection = session.entries.first?.id
        session.moveLandmark(.viewerLeftEye, toSourcePoint: Point2D(305, 402))

        _ = try CorrectionWriter.save(
            entries: session.entries, directory: session.directory,
            spec: session.spec, options: session.options, resampler: .coreGraphics,
            depth: OutputDepth(rawValue: session.bitDepth) ?? .sixteen
        )

        let tile = try #require(session.entries.first?.outputURL)
        #expect(try Self.bitsPerComponent(of: tile) == 8)
    }

    private static func bitsPerComponent(of url: URL) throws -> Int {
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        let properties = try #require(
            CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        )
        return try #require(properties[kCGImagePropertyDepth] as? Int)
    }
}
