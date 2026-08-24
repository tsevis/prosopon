import CoreGraphics
import Foundation
import ProsoponCore
import ProsoponIO
import ProsoponRender

/// Writes corrected tiles back over the run they came from, and updates the manifest.
///
/// Only edited tiles are re-rendered. Everything else is left byte-for-byte as it was,
/// so saving a single correction out of three hundred does not rewrite the batch.
public enum CorrectionWriter {

    public struct Summary: Sendable {
        public var rewritten: Int
        public var nowAccepted: Int
        public var nowRejected: Int
        public var failures: [String]
        /// The landmarks now on disk, by entry id, so the session can stop calling them
        /// unsaved. Only tiles this call actually dealt with are in here.
        public var written: [String: FaceLandmarks] = [:]

        public var describedOutcome: String {
            var parts = ["\(rewritten) tile\(rewritten == 1 ? "" : "s") rewritten"]
            if nowAccepted > 0 { parts.append("\(nowAccepted) newly accepted") }
            if nowRejected > 0 { parts.append("\(nowRejected) now rejected") }
            if !failures.isEmpty { parts.append("\(failures.count) failed") }
            return parts.joined(separator: ", ")
        }
    }

    public static func save(
        entries: [ReviewEntry],
        directory: URL,
        spec: CanvasSpec,
        options: SolveOptions,
        resampler: Resampler,
        format: ImageFormat = .png,
        depth: OutputDepth = .sixteen
    ) throws -> Summary {
        let edited = entries.filter(\.isEdited)
        guard !edited.isEmpty else {
            return Summary(rewritten: 0, nowAccepted: 0, nowRejected: 0, failures: [])
        }

        let renderer = (try? resampler.makeRenderer(spec: spec)) ?? CoreGraphicsRenderer(spec: spec)
        var summary = Summary(rewritten: 0, nowAccepted: 0, nowRejected: 0, failures: [])

        for entry in edited {
            do {
                try autoreleasepool {
                    guard let alignment = entry.alignment, let quality = entry.quality else {
                        summary.failures.append("\(entry.name): \(entry.failure ?? "unsolvable")")
                        return
                    }
                    // A correction can push a tile past the coverage gate in either
                    // direction, so the file has to follow the verdict.
                    let destination = entry.outputURL
                        ?? directory.appendingPathComponent("\(entry.name).\(format.fileExtension)")

                    if quality.isAccepted {
                        let image = try ImageLoading.load(entry.sourceURL)
                        let tile = try renderer.render(image, using: alignment.transform)
                        // At the run's depth, not at the default. Re-rendering an 8-bit
                        // run's tile at 16 leaves a 24 MB file beside its 6 MB neighbours
                        // and stores nothing the source ever carried.
                        try ImageWriting.write(tile, to: destination, format: format, depth: depth)
                        summary.rewritten += 1
                    } else if FileManager.default.fileExists(atPath: destination.path) {
                        try FileManager.default.removeItem(at: destination)
                        summary.nowRejected += 1
                    }
                    summary.written[entry.id] = entry.landmarks
                }
            } catch {
                summary.failures.append("\(entry.name): \(error)")
            }
        }

        try updateManifest(entries: entries, directory: directory, spec: spec, options: options)
        summary.nowAccepted = edited.filter { $0.quality?.isAccepted == true }.count
        return summary
    }

    /// Rewrites the manifest so a later `stack` or `qa` run sees the corrections.
    private static func updateManifest(
        entries: [ReviewEntry], directory: URL, spec: CanvasSpec, options: SolveOptions
    ) throws {
        let url = directory.appendingPathComponent("manifest.json")
        guard var manifest = try? JSONDecoder().decode(
            RunManifest.self, from: Data(contentsOf: url)
        ) else { return }

        var byID: [String: ReviewEntry] = [:]
        for entry in entries { byID["\(entry.sourceURL.path)#\(entry.faceIndex)"] = entry }

        manifest.tiles = manifest.tiles.map { record in
            guard let entry = byID["\(record.sourcePath)#\(record.faceIndex)"], entry.isEdited else {
                return record
            }
            var updated = record
            updated.landmarks = entry.landmarks
            updated.transform = entry.alignment?.transform
            updated.quality = entry.quality
            updated.rejections = entry.quality?.rejections ?? []
            updated.accepted = entry.quality?.isAccepted ?? false
            updated.nativeMouthDropRatio = entry.landmarks.mouthDropRatio
            if !(entry.quality?.isAccepted ?? false) { updated.outputPath = nil }
            return updated
        }

        // The caps travel with the run, and a correction may have been made under wider
        // ones than the run was aligned with. Recording the run's old numbers would
        // describe tiles that no longer exist, and would re-solve the correction against
        // a budget it was never made with the next time this folder is opened.
        manifest.maxStretch = options.maxStretch
        manifest.maxShear = options.maxShear

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(manifest).write(to: url)
    }
}
