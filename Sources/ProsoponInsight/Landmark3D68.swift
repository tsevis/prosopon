import CoreGraphics
import Foundation
import ProsoponCore

/// Head pose, in degrees, with the sign conventions the reference implementation uses.
public struct HeadPose: Hashable, Sendable, Codable {
    public var pitch: Double
    public var yaw: Double
    public var roll: Double
}

/// The 68-point 3-D landmark model, `1k3d68.onnx`, used here only for head pose.
///
/// Yaw is the one distortion the aligner cannot answer. A turned head foreshortens the
/// interocular distance, so pinning the eyes to their targets scales the whole face up
/// to compensate — and because the eye coordinates are fixed, there is no freedom left
/// to correct it. The only useful response is to measure it and decline the tile.
struct Landmark3D68 {
    static let inputSide = 192
    static let pointCount = 68

    let model: ONNXModel
    var interpolation: CGInterpolationQuality = .low

    /// Estimates pose by fitting the canonical mean face to what the model predicts.
    func pose(in image: CGImage, box: BoundingBox) throws -> HeadPose? {
        let transform = Landmark106.cropTransform(for: box)
        guard let tensor = ImageTensor.nchw(
            from: image, transform: transform,
            width: Self.inputSide, height: Self.inputSide,
            mean: 0, standardDeviation: 1,
            interpolation: interpolation
        ) else {
            throw InsightError.inferenceFailed("could not build the pose model's input tensor")
        }

        let outputs = try model.run(tensor, shape: [1, 3, Self.inputSide, Self.inputSide])
        guard let output = outputs.first, output.values.count >= Self.pointCount * 3 else {
            throw InsightError.unexpectedOutputs("expected at least \(Self.pointCount * 3) values")
        }

        // The model emits more points than are wanted; the 68 are the trailing ones.
        let values = Array(output.values.suffix(Self.pointCount * 3))
        let half = Double(Self.inputSide) / 2
        var predicted = [Double](repeating: 0, count: Self.pointCount * 3)
        for index in 0..<Self.pointCount {
            predicted[index * 3] = (Double(values[index * 3]) + 1) * half
            predicted[index * 3 + 1] = (Double(values[index * 3 + 1]) + 1) * half
            predicted[index * 3 + 2] = Double(values[index * 3 + 2]) * half
        }

        // Only the rotation matters, so the points can stay in crop space: the crop
        // transform is a similarity, which cannot introduce any rotation of its own.
        return Self.pose(fittingMeanShapeTo: predicted)
    }

    /// Least-squares fit of the mean face to `predicted`, then the Euler angles of the
    /// rotation that fit implies.
    static func pose(fittingMeanShapeTo predicted: [Double]) -> HeadPose? {
        guard predicted.count == pointCount * 3 else { return nil }
        guard let matrix = affineFit(from: MeanShape68.values, to: predicted),
              let rotation = rotation(from: matrix)
        else { return nil }
        return eulerAngles(of: rotation)
    }

    /// Solves `Y = P * [X; 1]` for the 3 x 4 affine `P`, by normal equations.
    ///
    /// With 68 correspondences and only four unknowns per row the system is heavily
    /// overdetermined and well conditioned, so a 4 x 4 solve is enough; nothing here
    /// needs a full decomposition.
    static func affineFit(from source: [Double], to target: [Double]) -> [Double]? {
        let count = pointCount
        var normal = [Double](repeating: 0, count: 16)     // 4 x 4
        var moment = [Double](repeating: 0, count: 12)     // 4 x 3

        for index in 0..<count {
            let homogeneous = [
                source[index * 3], source[index * 3 + 1], source[index * 3 + 2], 1,
            ]
            for row in 0..<4 {
                for column in 0..<4 {
                    normal[row * 4 + column] += homogeneous[row] * homogeneous[column]
                }
                for axis in 0..<3 {
                    moment[row * 3 + axis] += homogeneous[row] * target[index * 3 + axis]
                }
            }
        }

        guard let solution = solve4x4(normal, moment) else { return nil }
        // solution is 4 x 3 in row-major; the affine wants its transpose.
        var affine = [Double](repeating: 0, count: 12)
        for row in 0..<3 {
            for column in 0..<4 {
                affine[row * 4 + column] = solution[column * 3 + row]
            }
        }
        return affine
    }

    /// Gauss-Jordan with partial pivoting, for three right-hand sides at once.
    private static func solve4x4(_ matrix: [Double], _ rightHandSides: [Double]) -> [Double]? {
        var a = matrix
        var b = rightHandSides

        for column in 0..<4 {
            var pivot = column
            for row in (column + 1)..<4 where abs(a[row * 4 + column]) > abs(a[pivot * 4 + column]) {
                pivot = row
            }
            guard abs(a[pivot * 4 + column]) > 1e-12 else { return nil }
            if pivot != column {
                for k in 0..<4 { a.swapAt(column * 4 + k, pivot * 4 + k) }
                for k in 0..<3 { b.swapAt(column * 3 + k, pivot * 3 + k) }
            }
            let diagonal = a[column * 4 + column]
            for k in 0..<4 { a[column * 4 + k] /= diagonal }
            for k in 0..<3 { b[column * 3 + k] /= diagonal }

            for row in 0..<4 where row != column {
                let factor = a[row * 4 + column]
                guard factor != 0 else { continue }
                for k in 0..<4 { a[row * 4 + k] -= factor * a[column * 4 + k] }
                for k in 0..<3 { b[row * 3 + k] -= factor * b[column * 3 + k] }
            }
        }
        return b
    }

    /// Recovers a rotation from the affine's linear part.
    ///
    /// The first two rows are normalised and the third is their cross product, which
    /// discards the scale and any small non-orthogonality in the fit.
    ///
    /// A collapsed fit returns nil rather than an identity rotation. Reporting a
    /// degenerate result as "perfectly frontal" would quietly wave it through a yaw gate,
    /// which is the one outcome worse than reporting nothing.
    static func rotation(from affine: [Double]) -> [Double]? {
        func normalised(_ row: Int) -> [Double]? {
            let vector = [affine[row * 4], affine[row * 4 + 1], affine[row * 4 + 2]]
            let length = (vector[0] * vector[0] + vector[1] * vector[1] + vector[2] * vector[2]).squareRoot()
            return length > 1e-9 ? vector.map { $0 / length } : nil
        }
        guard let r1 = normalised(0), let r2 = normalised(1) else { return nil }
        let r3 = [
            r1[1] * r2[2] - r1[2] * r2[1],
            r1[2] * r2[0] - r1[0] * r2[2],
            r1[0] * r2[1] - r1[1] * r2[0],
        ]
        return r1 + r2 + r3
    }

    static func eulerAngles(of r: [Double]) -> HeadPose {
        let toDegrees = 180 / Double.pi
        let sy = (r[0] * r[0] + r[3] * r[3]).squareRoot()
        if sy < 1e-6 {
            // Gimbal lock: roll and yaw are no longer separable, so roll is pinned at 0.
            return HeadPose(
                pitch: atan2(-r[5], r[4]) * toDegrees,
                yaw: atan2(-r[6], sy) * toDegrees,
                roll: 0
            )
        }
        return HeadPose(
            pitch: atan2(r[7], r[8]) * toDegrees,
            yaw: atan2(-r[6], sy) * toDegrees,
            roll: atan2(r[3], r[0]) * toDegrees
        )
    }
}
