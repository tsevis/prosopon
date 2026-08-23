import CoreGraphics
import Foundation
import ProsoponCore

/// One face as the detector reports it, in source-image pixels.
struct SCRFDDetection {
    var box: BoundingBox
    var score: Double
    /// Five points, in the model's own order: both eyes, nose, both mouth corners.
    var keypoints: [Point2D]
}

/// SCRFD face detection, as published in `det_10g.onnx`.
///
/// The model emits nine tensors: a score, a box and five keypoints for every anchor at
/// each of three strides. They are matched to their stride by shape rather than by the
/// order the runtime happens to return them in — 12800, 3200 and 800 rows correspond to
/// strides 8, 16 and 32 over a 640 square with two anchors per cell.
struct SCRFD {
    static let inputSide = 640
    static let strides = [8, 16, 32]
    static let anchorsPerCell = 2
    /// The model was trained with inputs scaled to roughly [-1, 1].
    static let inputMean: Float = 127.5
    static let inputStandardDeviation: Float = 128.0

    let model: ONNXModel
    var scoreThreshold: Double = 0.5
    var iouThreshold: Double = 0.4

    /// Retried with the photograph inset by this fraction when the first pass finds
    /// nothing. SCRFD's largest anchors do not reach a face that fills its frame, so a
    /// tight head-and-shoulders crop is invisible until some space is put around it.
    /// Measured on 60 such crops: none found at all without this, all 60 with it.
    var retryMargin: Double = 0.5

    func detect(in image: CGImage) throws -> [SCRFDDetection] {
        let firstPass = try detect(in: image, margin: 0)
        guard firstPass.isEmpty, retryMargin > 0 else { return firstPass }
        return try detect(in: image, margin: retryMargin)
    }

    private func detect(in image: CGImage, margin: Double) throws -> [SCRFDDetection] {
        let transform = ImageTensor.letterbox(
            imageWidth: image.width, imageHeight: image.height,
            side: Self.inputSide, margin: margin
        )
        guard let inverse = transform.inverted else {
            throw InsightError.inferenceFailed("the letterbox is not invertible")
        }
        guard let tensor = ImageTensor.nchw(
            from: image, transform: transform,
            width: Self.inputSide, height: Self.inputSide,
            mean: Self.inputMean, standardDeviation: Self.inputStandardDeviation
        ) else {
            throw InsightError.inferenceFailed("could not build the detector's input tensor")
        }

        let outputs = try model.run(tensor, shape: [1, 3, Self.inputSide, Self.inputSide])
        var candidates: [SCRFDDetection] = []

        for stride in Self.strides {
            let cells = (Self.inputSide / stride) * (Self.inputSide / stride)
            let rows = cells * Self.anchorsPerCell
            guard let scores = outputs.first(where: { $0.rows == rows && $0.channels == 1 }),
                  let boxes = outputs.first(where: { $0.rows == rows && $0.channels == 4 }),
                  let keypoints = outputs.first(where: { $0.rows == rows && $0.channels == 10 })
            else {
                throw InsightError.unexpectedOutputs("no tensors with \(rows) rows for stride \(stride)")
            }
            candidates += decode(
                stride: stride, scores: scores, boxes: boxes,
                keypoints: keypoints, toImage: inverse
            )
        }

        return suppress(candidates)
    }

    private func decode(
        stride: Int, scores: ONNXTensor, boxes: ONNXTensor,
        keypoints: ONNXTensor, toImage: Affine2D
    ) -> [SCRFDDetection] {
        let width = Self.inputSide / stride
        var found: [SCRFDDetection] = []

        for row in 0..<scores.rows {
            let score = Double(scores.values[row])
            guard score >= scoreThreshold else { continue }

            // Anchors run row-major over the feature map, repeated per cell.
            let cell = row / Self.anchorsPerCell
            let centreX = Double((cell % width) * stride)
            let centreY = Double((cell / width) * stride)

            // The box is four distances from the anchor to each edge, in stride units.
            let base = row * 4
            let left = Double(boxes.values[base]) * Double(stride)
            let top = Double(boxes.values[base + 1]) * Double(stride)
            let right = Double(boxes.values[base + 2]) * Double(stride)
            let bottom = Double(boxes.values[base + 3]) * Double(stride)

            // Back out through the letterbox, which carries the inset as well as the scale.
            let topLeft = toImage.apply(to: Point2D(centreX - left, centreY - top))
            let bottomRight = toImage.apply(to: Point2D(centreX + right, centreY + bottom))

            var points: [Point2D] = []
            points.reserveCapacity(5)
            for index in 0..<5 {
                let offset = row * 10 + index * 2
                points.append(toImage.apply(to: Point2D(
                    centreX + Double(keypoints.values[offset]) * Double(stride),
                    centreY + Double(keypoints.values[offset + 1]) * Double(stride)
                )))
            }

            found.append(SCRFDDetection(
                box: BoundingBox(
                    x: topLeft.x, y: topLeft.y,
                    width: bottomRight.x - topLeft.x, height: bottomRight.y - topLeft.y
                ),
                score: score,
                keypoints: points
            ))
        }
        return found
    }

    /// Greedy non-maximum suppression, strongest box first.
    private func suppress(_ candidates: [SCRFDDetection]) -> [SCRFDDetection] {
        let ordered = candidates.sorted { $0.score > $1.score }
        var kept: [SCRFDDetection] = []
        for candidate in ordered {
            if kept.contains(where: { intersectionOverUnion($0.box, candidate.box) > iouThreshold }) {
                continue
            }
            kept.append(candidate)
        }
        return kept
    }

    private func intersectionOverUnion(_ a: BoundingBox, _ b: BoundingBox) -> Double {
        let x0 = max(a.x, b.x)
        let y0 = max(a.y, b.y)
        let x1 = min(a.x + a.width, b.x + b.width)
        let y1 = min(a.y + a.height, b.y + b.height)
        let overlap = max(0, x1 - x0) * max(0, y1 - y0)
        let union = a.area + b.area - overlap
        return union > 0 ? overlap / union : 0
    }
}
