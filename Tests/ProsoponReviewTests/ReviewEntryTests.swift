import Foundation
import ProsoponCore
import Testing
@testable import ProsoponReview

@Suite("Review entry")
struct ReviewEntryTests {

    private let spec = CanvasSpec.standard

    private func entry(
        // A 600 px interocular distance keeps magnification at 1.7, inside the default
        // gate; 400 would be enlarged 2.56 times and rejected before anything else runs.
        landmarks: FaceLandmarks = FaceLandmarks(
            viewerLeftEye: Point2D(400, 500),
            viewerRightEye: Point2D(1000, 500),
            mouth: Point2D(700, 1175)
        ),
        sourceSize: Int = 3000
    ) -> ReviewEntry {
        ReviewEntry(
            id: "t", sourceURL: URL(fileURLWithPath: "/tmp/t.jpg"), outputURL: nil, faceIndex: 0,
            sourceWidth: sourceSize, sourceHeight: sourceSize, detected: landmarks, spec: spec
        )
    }

    @Test("a fresh entry is solved and unedited")
    func freshEntryIsSolved() {
        let entry = entry()
        #expect(!entry.isEdited)
        #expect(entry.alignment != nil)
        #expect(entry.quality != nil)
        #expect(entry.failure == nil)
        #expect(entry.alignment!.eyeResidual < 1e-6)
    }

    // MARK: The drag contract

    @Test("dragging a marker onto a feature brings that feature to the target")
    func canvasDragLandsTheFeatureOnTarget() {
        // This is what a drag means, and the whole interaction rests on it: the reviewer
        // points at where the eye really is in the rendered tile, and after re-solving
        // that exact spot must sit on the crosshair.
        var subject = entry()
        let original = subject.alignment!.transform

        // Pretend the true left eye appears 37 px right and 21 px below the target.
        let pickedInCanvas = spec.viewerLeftEye + Point2D(37, -21)
        let featureInSource = original.inverted!.apply(to: pickedInCanvas)

        subject.setLandmark(.viewerLeftEye, toCanvasPoint: pickedInCanvas, spec: spec)

        let landed = subject.alignment!.transform.apply(to: featureInSource)
        #expect(landed.distance(to: spec.viewerLeftEye) < 1e-6,
                "the picked feature landed at \(landed), not on \(spec.viewerLeftEye)")
        #expect(subject.isEdited)
    }

    @Test("the same contract holds for the right eye")
    func canvasDragWorksForTheRightEye() {
        var subject = entry()
        let original = subject.alignment!.transform
        let picked = spec.viewerRightEye + Point2D(-18, 44)
        let feature = original.inverted!.apply(to: picked)

        subject.setLandmark(.viewerRightEye, toCanvasPoint: picked, spec: spec)
        #expect(subject.alignment!.transform.apply(to: feature).distance(to: spec.viewerRightEye) < 1e-6)
    }

    @Test("correcting the mouth moves it towards its target")
    func mouthCorrectionImproves() {
        // The mouth is only placed exactly when the stretch and shear stay inside their
        // caps, so the guarantee here is improvement rather than exactness.
        var subject = entry(landmarks: FaceLandmarks(
            viewerLeftEye: Point2D(400, 500),
            viewerRightEye: Point2D(1000, 500),
            mouth: Point2D(700, 1040)         // far too high, so the stretch will clamp
        ))
        let before = subject.alignment!.mouthResidual.length
        #expect(before > 1, "this fixture is meant to start off target")

        let picked = subject.alignment!.transform.apply(to: Point2D(700, 1175))
        subject.setLandmark(.mouth, toCanvasPoint: picked, spec: spec)
        #expect(subject.alignment!.mouthResidual.length < before)
    }

    @Test("editing a landmark leaves the other two alone")
    func editingIsLocal() {
        var subject = entry()
        let before = subject.landmarks
        subject.setLandmark(.mouth, toSourcePoint: Point2D(710, 1180), spec: spec)
        #expect(subject.landmarks.viewerLeftEye == before.viewerLeftEye)
        #expect(subject.landmarks.viewerRightEye == before.viewerRightEye)
        #expect(subject.landmarks.mouth == Point2D(710, 1180))
    }

    @Test("reverting restores exactly what the detector produced")
    func revertRestoresDetection() {
        var subject = entry()
        let original = subject.landmarks
        subject.setLandmark(.viewerLeftEye, toSourcePoint: Point2D(1, 2), spec: spec)
        #expect(subject.isEdited)
        subject.revert(spec: spec)
        #expect(!subject.isEdited)
        #expect(subject.landmarks == original)
        #expect(subject.alignment != nil)
    }

    @Test("an unsolvable edit is reported rather than crashing")
    func unsolvableEditIsCaught() {
        var subject = entry()
        // Both eyes in the same place: no scale or rotation is recoverable.
        subject.setLandmark(.viewerLeftEye, toSourcePoint: Point2D(1000, 500), spec: spec)
        #expect(subject.alignment == nil)
        #expect(subject.failure != nil)
        #expect(subject.quality == nil)
    }

    @Test("a canvas drag on an unsolvable entry is ignored rather than guessing")
    func canvasDragNeedsATransform() {
        var subject = entry()
        subject.setLandmark(.viewerLeftEye, toSourcePoint: Point2D(1000, 500), spec: spec)
        let broken = subject.landmarks
        subject.setLandmark(.mouth, toCanvasPoint: Point2D(1024, 1664), spec: spec)
        #expect(subject.landmarks == broken, "without a transform there is nothing to map through")
    }

    @Test("triage puts failures first, then rejects, then low scores")
    func triageOrdering() {
        let good = entry()
        // A tiny source cannot cover the canvas, so this one is rejected.
        let rejected = entry(sourceSize: 900)
        var broken = entry()
        broken.setLandmark(.viewerLeftEye, toSourcePoint: Point2D(1000, 500), spec: spec)

        let sorted = [good, rejected, broken].sorted { $0.triageRank < $1.triageRank }
        #expect(sorted[0].failure != nil)
        #expect(sorted[1].quality?.isAccepted == false)
        #expect(sorted[2].quality?.isAccepted == true)
    }
}

@Suite("Canvas geometry")
struct CanvasGeometryTests {

    @Test("a point survives the round trip to the view and back")
    func roundTrip() {
        let geometry = CanvasGeometry(canvasSize: 2048, availableSize: CGSize(width: 900, height: 700))
        for point in [Point2D(0, 0), Point2D(512, 512), Point2D(1024, 1664), Point2D(2048, 2048)] {
            let back = geometry.canvasPoint(geometry.viewPoint(point))
            #expect(abs(back.x - point.x) < 1e-9)
            #expect(abs(back.y - point.y) < 1e-9)
        }
    }

    @Test("the canvas is centred in whichever direction has room to spare")
    func centring() {
        let wide = CanvasGeometry(canvasSize: 2048, availableSize: CGSize(width: 1000, height: 600))
        #expect(wide.frame.width == 600, "the square is limited by the shorter side")
        #expect(abs(wide.frame.minX - 200) < 1e-9)
        #expect(abs(wide.frame.minY) < 1e-9)

        let tall = CanvasGeometry(canvasSize: 2048, availableSize: CGSize(width: 500, height: 900))
        #expect(tall.frame.height == 500)
        #expect(abs(tall.frame.minY - 200) < 1e-9)
    }

    @Test("the targets land where they should on screen")
    func targetsMapToExpectedPlaces() {
        let geometry = CanvasGeometry(canvasSize: 2048, availableSize: CGSize(width: 512, height: 512))
        let leftEye = geometry.viewPoint(CanvasSpec.standard.viewerLeftEye)
        #expect(abs(leftEye.x - 128) < 1e-9, "512/2048 of the way across")
        #expect(abs(leftEye.y - 128) < 1e-9)
        let mouth = geometry.viewPoint(CanvasSpec.standard.mouth)
        #expect(abs(mouth.x - 256) < 1e-9)
        #expect(abs(mouth.y - 416) < 1e-9)
    }

    @Test("a zero-sized area does not divide by zero")
    func degenerateSize() {
        let geometry = CanvasGeometry(canvasSize: 2048, availableSize: .zero)
        #expect(geometry.frame.width == 1)
        #expect(geometry.scale > 0)
    }
}
