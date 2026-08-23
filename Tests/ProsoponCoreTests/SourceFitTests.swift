import Foundation
import Testing
@testable import ProsoponCore

@Suite("SourceFit")
struct SourceFitTests {

    /// A face at 1.125 with interocular `d`, centred in a `w` x `h` image.
    private func face(interocular d: Double, in size: (w: Double, h: Double)) -> FaceLandmarks {
        let center = Point2D(size.w / 2, size.h * 0.35)
        return FaceLandmarks(
            viewerLeftEye: Point2D(center.x - d / 2, center.y),
            viewerRightEye: Point2D(center.x + d / 2, center.y),
            mouth: Point2D(center.x, center.y + 1.125 * d)
        )
    }

    @Test("a generously framed portrait covers the canvas completely")
    func generousFramingIsFullyCovered() throws {
        // Interocular 400 in a 4000 x 4000 frame: the canvas needs 0.5 interocular
        // above the eye line and 1.5 below, which is 200 px and 600 px here.
        let size = (w: 4000.0, h: 4000.0)
        let alignment = try AlignmentSolver.solve(landmarks: face(interocular: 400, in: size))
        let fit = SourceFit.evaluate(alignment: alignment, sourceWidth: size.w, sourceHeight: size.h)
        #expect(fit.isFullyCovered)
        #expect(abs(fit.coverage - 1) < 1e-6)
    }

    @Test("a tight crop leaves the canvas short and is caught")
    func tightCropIsNotFullyCovered() throws {
        // Interocular 900 in a 1000 x 1000 frame: only 50 px sits outside each eye,
        // where the canvas wants 450.
        let size = (w: 1000.0, h: 1000.0)
        let alignment = try AlignmentSolver.solve(landmarks: face(interocular: 900, in: size))
        let fit = SourceFit.evaluate(alignment: alignment, sourceWidth: size.w, sourceHeight: size.h)
        #expect(!fit.isFullyCovered)
        #expect(fit.coverage < 1)
        #expect(fit.coverage > 0)
    }

    @Test("coverage is exactly 1 when the mapped source strictly contains the canvas")
    func coverageSaturatesAtOne() throws {
        let size = (w: 8000.0, h: 8000.0)
        let alignment = try AlignmentSolver.solve(landmarks: face(interocular: 300, in: size))
        let fit = SourceFit.evaluate(alignment: alignment, sourceWidth: size.w, sourceHeight: size.h)
        #expect(fit.coverage == 1 || abs(fit.coverage - 1) < 1e-9)
    }

    @Test("the source quad is the crop the photograph would have needed")
    func sourceQuadIsTheRequiredCrop() throws {
        let size = (w: 4000.0, h: 4000.0)
        let d = 400.0
        let alignment = try AlignmentSolver.solve(landmarks: face(interocular: d, in: size))
        let fit = SourceFit.evaluate(alignment: alignment, sourceWidth: size.w, sourceHeight: size.h)

        // Canvas is 2 interocular distances across, so the crop is 2 * 400 = 800 px wide.
        let width = fit.sourceQuad[1].distance(to: fit.sourceQuad[0])
        #expect(abs(width - 800) < 1e-6)
    }

    @Test("quality gate rejects incomplete coverage by default")
    func gateRejectsPartialCoverage() throws {
        let size = (w: 1000.0, h: 1000.0)
        let alignment = try AlignmentSolver.solve(landmarks: face(interocular: 900, in: size))
        let fit = SourceFit.evaluate(alignment: alignment, sourceWidth: size.w, sourceHeight: size.h)
        let report = QualityReport.evaluate(alignment: alignment, fit: fit)
        #expect(!report.isAccepted)
        #expect(report.rejections.contains(.incompleteCoverage))
    }

    @Test("quality gate accepts a well framed high resolution portrait")
    func gateAcceptsGoodPortrait() throws {
        let size = (w: 6000.0, h: 6000.0)
        let alignment = try AlignmentSolver.solve(landmarks: face(interocular: 1200, in: size))
        let fit = SourceFit.evaluate(alignment: alignment, sourceWidth: size.w, sourceHeight: size.h)
        let report = QualityReport.evaluate(alignment: alignment, fit: fit)
        #expect(report.isAccepted)
        #expect(report.magnification < 1, "1200 px interocular downsamples to the 1024 target")
        #expect(report.score > 0.9)
    }
}
