import Foundation
import ProsoponCore
import Testing
@testable import ProsoponReview

/// The queue's appearance for tiles that have no picture, and the yaw the detector
/// reported travelling from the manifest to the metrics.
@Suite("Tile export state")
struct TileExportStateTests {

    private let spec = CanvasSpec.standard

    /// A 600 px interocular distance keeps magnification inside the default gate.
    private func landmarks(mouthDrop: Double = 675) -> FaceLandmarks {
        FaceLandmarks(
            viewerLeftEye: Point2D(400, 500),
            viewerRightEye: Point2D(1000, 500),
            mouth: Point2D(700, 500 + mouthDrop)
        )
    }

    private func entry(
        outputURL: URL? = URL(fileURLWithPath: "/tmp/tile.png"),
        sourceSize: Int = 3000,
        yaw: Double? = nil
    ) -> ReviewEntry {
        ReviewEntry(
            id: "t", sourceURL: URL(fileURLWithPath: "/tmp/t.jpg"),
            outputURL: outputURL, faceIndex: 0,
            sourceWidth: sourceSize, sourceHeight: sourceSize,
            detected: landmarks(), detectedYawDegrees: yaw, spec: spec
        )
    }

    // MARK: A tile that was written

    @Test("an accepted tile with a file on record is exported, and says nothing extra")
    func acceptedTileIsExported() {
        let subject = entry()
        #expect(subject.quality?.isAccepted == true)
        #expect(subject.exportState == .exported(URL(fileURLWithPath: "/tmp/tile.png")))
        #expect(subject.exportState.caption == nil)
        #expect(!subject.exportState.isTrouble)
    }

    // MARK: A tile that was declined

    @Test("a rejected tile is not exported, and names what declined it")
    func rejectedTileNamesItsGate() throws {
        // A source too small for the canvas cannot fill it once the eyes are pinned.
        let subject = entry(outputURL: nil, sourceSize: 700)
        let quality = try #require(subject.quality)

        #expect(!quality.isAccepted)
        #expect(quality.rejections.contains(.incompleteCoverage))
        #expect(subject.exportState == .notExported(quality.rejections))

        // The wording is the reviewer's, not the enum's. `incompleteCoverage` is a gate
        // name; "does not fill the canvas" is what happened to the photograph.
        let caption = try #require(subject.exportState.caption)
        #expect(caption.hasPrefix("Not exported"))
        #expect(caption.contains("does not fill the canvas"))
        #expect(!caption.contains("incompleteCoverage"))
    }

    @Test("a declined tile is a decision, not a fault")
    func declinedIsNotTrouble() {
        // The whole reason this type exists: a black square reads as a broken thumbnail.
        // Deliberately not exported has to look different from something going wrong.
        #expect(!entry(outputURL: nil, sourceSize: 700).exportState.isTrouble)
        #expect(TileExportState.unsolvable("no").isTrouble)
        #expect(TileExportState.missing(URL(fileURLWithPath: "/tmp/gone.png")).isTrouble)
    }

    @Test("an unsolvable tile reports the solve, not a gate")
    func unsolvableTile() {
        // Eyes on the same point: there is no interocular distance to scale from.
        let degenerate = FaceLandmarks(
            viewerLeftEye: Point2D(500, 500),
            viewerRightEye: Point2D(500, 500),
            mouth: Point2D(500, 900)
        )
        let subject = ReviewEntry(
            id: "t", sourceURL: URL(fileURLWithPath: "/tmp/t.jpg"), outputURL: nil,
            faceIndex: 0, sourceWidth: 3000, sourceHeight: 3000, detected: degenerate, spec: spec
        )
        #expect(subject.failure != nil)
        if case .unsolvable = subject.exportState {} else {
            Issue.record("expected unsolvable, got \(subject.exportState)")
        }
        #expect(subject.exportState.caption == "No tile \u{00B7} could not be solved")
    }

    @Test("an accepted tile with no file recorded was a dry run")
    func analysedOnly() {
        let subject = entry(outputURL: nil)
        #expect(subject.quality?.isAccepted == true)
        #expect(subject.exportState == .analysedOnly)
        #expect(subject.exportState.caption == "Analysed only \u{00B7} no file written")
    }

    @Test("every state offers a symbol, and only the exported one offers no caption")
    func everyStateIsDrawable() {
        let states: [TileExportState] = [
            .exported(URL(fileURLWithPath: "/tmp/a.png")),
            .notExported([.incompleteCoverage]),
            .unsolvable("why"),
            .analysedOnly,
            .missing(URL(fileURLWithPath: "/tmp/a.png")),
        ]
        for state in states {
            #expect(!state.symbolName.isEmpty)
            #expect((state.caption == nil) == (state == .exported(URL(fileURLWithPath: "/tmp/a.png"))))
        }
    }

    @Test("every rejection reason has wording of its own")
    func everyReasonIsPhrased() {
        // A reason added later without a phrase would otherwise silently print the
        // enum's own spelling in the queue.
        var seen: Set<String> = []
        for reason in RejectionReason.allCases {
            let phrase = TileExportState.phrase(reason)
            #expect(phrase != reason.rawValue)
            #expect(seen.insert(phrase).inserted, "\(reason) reuses another reason's wording")
        }
    }
}

// MARK: - Yaw

@Suite("Detector yaw")
struct DetectorYawTests {

    private let spec = CanvasSpec.standard

    private func entry(yaw: Double?) -> ReviewEntry {
        ReviewEntry(
            id: "t", sourceURL: URL(fileURLWithPath: "/tmp/t.jpg"), outputURL: nil, faceIndex: 0,
            sourceWidth: 3000, sourceHeight: 3000,
            detected: FaceLandmarks(
                viewerLeftEye: Point2D(400, 500),
                viewerRightEye: Point2D(1000, 500),
                mouth: Point2D(700, 1175)
            ),
            detectedYawDegrees: yaw, spec: spec
        )
    }

    @Test("the detector's yaw reaches the quality report")
    func yawReachesTheReport() {
        // The solve cannot recover yaw from three points, so if it is not carried through
        // it is gone -- which is what made the panel read "not measured" over a manifest
        // that held a value.
        #expect(entry(yaw: -17.5).quality?.yawDegrees == -17.5)
        #expect(entry(yaw: nil).quality?.yawDegrees == nil)
    }

    @Test("a reported zero is not the same as nothing reported")
    func zeroIsNotAbsent() {
        // Vision quantises yaw to 45 degree steps and reports 0 for a frontal face. That
        // is a measurement; treating it as absent is what the bug did.
        #expect(entry(yaw: 0).quality?.yawDegrees == 0)
    }

    @Test("yaw survives a correction and a revert")
    func yawSurvivesEditing() {
        var subject = entry(yaw: 31)
        subject.setLandmark(.viewerLeftEye, toCanvasPoint: spec.viewerLeftEye + Point2D(20, 8), spec: spec)
        #expect(subject.isEdited)
        #expect(subject.quality?.yawDegrees == 31)

        subject.revert(spec: spec)
        #expect(!subject.isEdited)
        #expect(subject.quality?.yawDegrees == 31)
    }

    @Test("a turned head scores below a frontal one")
    func yawPenalisesTheScore() {
        // Yaw feeds the score, so threading it through also changes the worst-first
        // ordering -- for detectors that report a yaw worth having.
        let frontal = entry(yaw: 0)
        let turned = entry(yaw: 40)
        #expect(turned.quality!.score < frontal.quality!.score)
        #expect(turned.triageRank < frontal.triageRank)
    }
}
