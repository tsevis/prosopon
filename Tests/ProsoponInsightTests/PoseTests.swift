import CoreGraphics
import Foundation
import ProsoponCore
import ProsoponIO
import Testing
@testable import ProsoponInsight

struct PoseTruth: Decodable {
    struct Face: Decodable {
        var bbox: [Double]
        var pose: [Double]          // pitch, yaw, roll
    }
    var faces: [Face]
}

@Suite("Head pose")
struct PoseTests {

    static var available: Bool {
        FileManager.default.fileExists(
            atPath: ParityTests.fixtures.appendingPathComponent("pose_truth.json").path
        ) && ((try? ModelBundle.locate())?.pose != nil)
    }

    @Test("yaw agrees with the reference implementation", .enabled(if: available))
    func yawParity() throws {
        let image = try ImageLoading.load(ParityTests.fixtures.appendingPathComponent("t1.jpg"))
        let truth = try JSONDecoder().decode(
            PoseTruth.self,
            from: Data(contentsOf: ParityTests.fixtures.appendingPathComponent("pose_truth.json"))
        )
        let bundle = try ModelBundle.locate()
        let stage = Landmark3D68(model: try ONNXModel(path: try #require(bundle.pose)))

        var worstYaw = 0.0
        var worstPitch = 0.0
        for reference in truth.faces {
            let box = BoundingBox(
                x: reference.bbox[0], y: reference.bbox[1],
                width: reference.bbox[2] - reference.bbox[0],
                height: reference.bbox[3] - reference.bbox[1]
            )
            let pose = try #require(try stage.pose(in: image, box: box))
            worstYaw = max(worstYaw, abs(pose.yaw - reference.pose[1]))
            worstPitch = max(worstPitch, abs(pose.pitch - reference.pose[0]))
            print(String(format: "POSE yaw %7.2f vs %7.2f   pitch %7.2f vs %7.2f",
                         pose.yaw, reference.pose[1], pose.pitch, reference.pose[0]))
        }
        print(String(format: "POSE worst yaw %.2f deg, worst pitch %.2f deg", worstYaw, worstPitch))
        // Measured across yaws from -55 to +7 degrees. The residue is the same
        // resampling difference that shows up everywhere else in this comparison.
        #expect(worstYaw < 1.5, "worst yaw \(worstYaw) degrees")
        #expect(worstPitch < 1.5, "worst pitch \(worstPitch) degrees")
    }

    // MARK: The maths, with no model involved

    @Test("a pure rotation is recovered from the fit")
    func recoversAKnownRotation() throws {
        // Rotate the mean face by a known yaw and check the fit reads it back.
        for expected in [-40.0, -15.0, 0.0, 22.5, 51.0] {
            let radians = expected * .pi / 180
            var rotated = [Double](repeating: 0, count: 68 * 3)
            for index in 0..<68 {
                let x = MeanShape68.values[index * 3]
                let y = MeanShape68.values[index * 3 + 1]
                let z = MeanShape68.values[index * 3 + 2]
                // Yaw about the vertical axis, then an arbitrary scale and offset that
                // the fit is supposed to absorb.
                rotated[index * 3] = (cos(radians) * x + sin(radians) * z) * 3.7 + 100
                rotated[index * 3 + 1] = y * 3.7 - 40
                rotated[index * 3 + 2] = (-sin(radians) * x + cos(radians) * z) * 3.7 + 7
            }
            let pose = try #require(Landmark3D68.pose(fittingMeanShapeTo: rotated))
            #expect(abs(pose.yaw - expected) < 0.5, "read \(pose.yaw) for a yaw of \(expected)")
            #expect(abs(pose.pitch) < 0.5)
            #expect(abs(pose.roll) < 0.5)
        }
    }

    @Test("the identity fit reports no rotation at all")
    func identityIsNeutral() throws {
        let pose = try #require(Landmark3D68.pose(fittingMeanShapeTo: MeanShape68.values))
        #expect(abs(pose.yaw) < 1e-6)
        #expect(abs(pose.pitch) < 1e-6)
        #expect(abs(pose.roll) < 1e-6)
    }

    @Test("scale and translation alone are not mistaken for rotation")
    func similarityIsNotRotation() throws {
        var moved = [Double](repeating: 0, count: 68 * 3)
        for index in 0..<(68 * 3) {
            moved[index] = MeanShape68.values[index] * 12.5 + Double(index % 3) * 30
        }
        let pose = try #require(Landmark3D68.pose(fittingMeanShapeTo: moved))
        #expect(abs(pose.yaw) < 1e-6)
        #expect(abs(pose.pitch) < 1e-6)
        #expect(abs(pose.roll) < 1e-6)
    }

    @Test("a degenerate point set is refused rather than returning nonsense")
    func degenerateFitIsRefused() {
        #expect(Landmark3D68.pose(fittingMeanShapeTo: [Double](repeating: 0, count: 68 * 3)) == nil)
        #expect(Landmark3D68.pose(fittingMeanShapeTo: [1, 2, 3]) == nil)
    }
}
