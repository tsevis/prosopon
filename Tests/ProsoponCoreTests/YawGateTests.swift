import Foundation
import Testing
@testable import ProsoponCore

@Suite("Yaw gate")
struct YawGateTests {

    private let spec = CanvasSpec.standard

    /// A well-framed frontal face that clears every other gate.
    private func solved() throws -> (Alignment, SourceFit) {
        let landmarks = FaceLandmarks(
            viewerLeftEye: Point2D(1200, 1000),
            viewerRightEye: Point2D(2200, 1000),
            mouth: Point2D(1700, 2125)
        )
        let alignment = try AlignmentSolver.solve(landmarks: landmarks, spec: spec)
        let fit = SourceFit.evaluate(
            alignment: alignment, sourceWidth: 6000, sourceHeight: 6000, spec: spec
        )
        return (alignment, fit)
    }

    @Test("a turned head is rejected once it passes the limit")
    func rejectsBeyondTheLimit() throws {
        let (alignment, fit) = try solved()
        let thresholds = QualityThresholds(maxYawDegrees: 15)

        let frontal = QualityReport.evaluate(
            alignment: alignment, fit: fit, yawDegrees: 4, thresholds: thresholds
        )
        #expect(frontal.isAccepted)

        let turned = QualityReport.evaluate(
            alignment: alignment, fit: fit, yawDegrees: 31, thresholds: thresholds
        )
        #expect(!turned.isAccepted)
        #expect(turned.rejections.contains(.excessiveYaw))
    }

    @Test("the limit applies to a turn in either direction")
    func symmetric() throws {
        let (alignment, fit) = try solved()
        let thresholds = QualityThresholds(maxYawDegrees: 20)
        for yaw in [-42.0, 42.0] {
            let report = QualityReport.evaluate(
                alignment: alignment, fit: fit, yawDegrees: yaw, thresholds: thresholds
            )
            #expect(report.rejections.contains(.excessiveYaw), "yaw \(yaw) should be refused")
        }
    }

    @Test("a detector that reports no yaw cannot fail the gate")
    func silenceIsNotAFailure() throws {
        // Silence is not evidence of a frontal face; inventing a zero would be worse
        // than admitting the measurement was never made.
        let (alignment, fit) = try solved()
        let report = QualityReport.evaluate(
            alignment: alignment, fit: fit, yawDegrees: nil,
            thresholds: QualityThresholds(maxYawDegrees: 5)
        )
        #expect(report.isAccepted)
        #expect(report.yawDegrees == nil)
    }

    @Test("by default no pose is refused")
    func defaultIsOpen() throws {
        let (alignment, fit) = try solved()
        let report = QualityReport.evaluate(alignment: alignment, fit: fit, yawDegrees: 70)
        #expect(report.isAccepted)
        #expect(report.yawDegrees == 70)
    }

    @Test("the score falls off with yaw even when nothing is rejected")
    func scoreFavoursFrontalFaces() throws {
        // Sorting by score should bring the most frontal tiles forward, not only
        // separate the accepted from the refused.
        let (alignment, fit) = try solved()
        let scores = [0.0, 15.0, 30.0, 60.0].map {
            QualityReport.evaluate(alignment: alignment, fit: fit, yawDegrees: $0).score
        }
        #expect(scores == scores.sorted(by: >), "scores \(scores) should fall as yaw grows")
        #expect(scores[0] > scores[3] * 1.5)
    }

    @Test("yaw does not disturb the other gates")
    func independentOfOtherGates() throws {
        let (alignment, fit) = try solved()
        let report = QualityReport.evaluate(
            alignment: alignment, fit: fit, yawDegrees: 80,
            thresholds: QualityThresholds(maxYawDegrees: 20)
        )
        #expect(report.rejections == [.excessiveYaw], "only the pose gate should object")
        #expect(report.coverage == 1)
    }
}
