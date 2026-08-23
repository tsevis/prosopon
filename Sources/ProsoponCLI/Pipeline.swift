import CoreGraphics
import Foundation
import ProsoponCore
import ProsoponIO
import ProsoponRender
import ProsoponVision

struct OutputPlan: Sendable {
    var directory: URL
    var overlayDirectory: URL?
    var format: ImageFormat
}

/// Load, detect, solve, gate, render — for one photograph.
///
/// Everything here is value types and locals, so a task group can run one instance of
/// `process` per image with no shared mutable state and no CGImage crossing a task boundary.
struct Pipeline: Sendable {
    var spec: CanvasSpec
    var solveOptions: SolveOptions
    var thresholds: QualityThresholds
    var selection: FaceSelection
    var detector: VisionLandmarkDetector
    var renderer: any TileRenderer
    var output: OutputPlan?

    func process(_ url: URL) -> [TileRecord] {
        let image: CGImage
        do {
            image = try ImageLoading.load(url)
        } catch {
            return [.failed(source: url, width: 0, height: 0, faceIndex: 0, message: "\(error)")]
        }

        let width = Double(image.width)
        let height = Double(image.height)

        let detected: [DetectedFace]
        do {
            detected = try detector.detect(in: image)
        } catch {
            return [.failed(source: url, width: image.width, height: image.height, faceIndex: 0, message: "detection failed: \(error)")]
        }

        let chosen = selection.choose(from: detected, imageWidth: width, imageHeight: height)
        guard !chosen.isEmpty else {
            return [.failed(source: url, width: image.width, height: image.height, faceIndex: 0, message: "no face detected")]
        }

        return chosen.enumerated().map { index, face in
            tile(for: face, index: index, total: chosen.count, image: image, url: url)
        }
    }

    private func tile(
        for face: DetectedFace, index: Int, total: Int, image: CGImage, url: URL
    ) -> TileRecord {
        var record = TileRecord(
            sourcePath: url.path,
            sourceWidth: image.width,
            sourceHeight: image.height,
            faceIndex: index,
            outputPath: nil,
            accepted: false,
            rejections: [],
            failure: nil,
            landmarks: face.landmarks,
            nativeMouthDropRatio: face.landmarks.mouthDropRatio,
            detectorConfidence: face.confidence,
            yawDegrees: face.yawDegrees,
            pitchDegrees: face.pitchDegrees
        )

        let alignment: Alignment
        do {
            alignment = try AlignmentSolver.solve(landmarks: face.landmarks, spec: spec, options: solveOptions)
        } catch {
            record.failure = "\(error)"
            return record
        }

        let fit = SourceFit.evaluate(
            alignment: alignment,
            sourceWidth: Double(image.width),
            sourceHeight: Double(image.height),
            spec: spec
        )
        let quality = QualityReport.evaluate(alignment: alignment, fit: fit, thresholds: thresholds)

        record.transform = alignment.transform
        record.quality = quality
        record.rejections = quality.rejections
        record.accepted = quality.isAccepted

        guard quality.isAccepted, let output else { return record }

        do {
            record.outputPath = try render(image, alignment: alignment, url: url, index: index, total: total, output: output)
        } catch {
            record.accepted = false
            record.failure = "render failed: \(error)"
        }
        return record
    }

    private func render(
        _ image: CGImage, alignment: Alignment, url: URL, index: Int, total: Int, output: OutputPlan
    ) throws -> String {
        let stem = url.deletingPathExtension().lastPathComponent
        let name = total > 1 ? "\(stem)_f\(index)" : stem

        let tile = try renderer.render(image, using: alignment.transform)

        let destination = output.directory.appendingPathComponent("\(name).\(output.format.fileExtension)")
        try ImageWriting.write(tile, to: destination, format: output.format)

        if let overlayDirectory = output.overlayDirectory,
           let overlaid = OverlayRenderer(spec: spec).draw(over: tile) {
            let overlayURL = overlayDirectory.appendingPathComponent("\(name).png")
            try ImageWriting.write(overlaid, to: overlayURL, format: .png)
        }

        return destination.path
    }
}
