import CoreGraphics
import Foundation
import ProsoponCore
import ProsoponIO
import ProsoponPipeline
import Testing
@testable import ProsoponMix

/// A whole mix run, over tiles written to disk and a manifest written by `RunWriter`.
///
/// Everything here is read back from what the real writers produced rather than from a
/// fixture shaped the way the reader expects. This project has already been bitten once by
/// a hand-written fixture that agreed with a reader they were both wrong about.
@Suite("Mix run")
struct MixRunTests {

    /// Small enough to run in milliseconds, quartered exactly like the real canvas:
    /// 64 px canvas, 32 px quadrants, mouth at (32, 52) — still on the vertical seam and
    /// still in the bottom half.
    private let spec = CanvasSpec.standard.scaled(toSize: 64)
    private let side = 64
    private let tileCount = 8

    private var options: MixOptions {
        MixOptions(
            seed: 1, seamWidth: 4, mouthBandHeight: 12, measureSize: 64,
            format: .psd, previewSize: 64, concurrency: 4
        )
    }

    // MARK: Fixtures

    private func temporary() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("prosopon-mixrun-\(UInt64.random(in: 0...UInt64.max))")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Tile `index` gets a distinct red in every quadrant and a green that names the
    /// quadrant, so a pixel of the finished composite says both which tile it came from
    /// and which quarter of that tile it is.
    private func red(forTile index: Int) -> Int { 20 + 30 * index }
    private func green(for quadrant: Quadrant) -> Int {
        40 + 50 * (Quadrant.allCases.firstIndex(of: quadrant) ?? 0)
    }

    private func writeTiles(into folder: URL, detector: String) throws -> [URL] {
        var urls: [URL] = []
        var records: [TileRecord] = []

        for index in 0..<tileCount {
            let url = folder.appendingPathComponent(String(format: "tile%02d.png", index))
            try writeQuarteredTile(to: url, red: red(forTile: index))
            urls.append(url)
            // Half the corpus turned, half frontal, so the pool split is checkable.
            let yaw = index < 4 ? Double(index) : Double(20 + index)
            records.append(TileRecord(
                sourcePath: "/tmp/sources/tile\(index).jpg",
                sourceWidth: side, sourceHeight: side, faceIndex: 0,
                outputPath: url.path, accepted: true,
                quality: try quality(yaw: yaw),
                yawDegrees: yaw
            ))
        }

        // Written by the real producer, so the catalogue is reading the same shape
        // `prosopon align` leaves behind rather than one invented here.
        try RunWriter.write(
            records, to: folder, spec: spec, solveOptions: .default,
            detector: detector, resampler: "lanczos"
        )
        return urls
    }

    /// A real quality report, solved by the real solver, so the manifest carries the same
    /// shape an align run would leave behind — including the score the mix falls back to
    /// when the detector's yaw is not worth trusting.
    private func quality(yaw: Double) throws -> QualityReport {
        // Landmarks already on their targets: the transform is the identity and the tile
        // covers the canvas, so the only thing separating these scores is the pose term.
        let landmarks = FaceLandmarks(
            viewerLeftEye: spec.viewerLeftEye,
            viewerRightEye: spec.viewerRightEye,
            mouth: spec.mouth
        )
        let alignment = try AlignmentSolver.solve(landmarks: landmarks, spec: spec, options: .default)
        let fit = SourceFit.evaluate(
            alignment: alignment, sourceWidth: Double(side), sourceHeight: Double(side), spec: spec
        )
        return QualityReport.evaluate(alignment: alignment, fit: fit, yawDegrees: yaw)
    }

    private func writeQuarteredTile(to url: URL, red: Int) throws {
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try #require(CGContext(
            data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
            space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        let half = side / 2
        for quadrant in Quadrant.allCases {
            let origin = QuadrantGrid(spec: spec).origin(of: quadrant)
            context.setFillColor(
                red: Double(red) / 255,
                green: Double(green(for: quadrant)) / 255,
                blue: 0.5, alpha: 1
            )
            // Core Graphics counts y from the bottom; the quadrant origins count from the top.
            context.fill(CGRect(
                x: origin.x, y: side - origin.y - half, width: half, height: half
            ))
        }
        try ImageWriting.write(try #require(context.makeImage()), to: url, format: .png, depth: .eight)
    }

    // MARK: The run

    @Test("a run writes a document per composite, a preview, a manifest and a report")
    func writesWhatItSays() async throws {
        let root = try temporary()
        defer { try? FileManager.default.removeItem(at: root) }
        let tiles = root.appendingPathComponent("aligned")
        try FileManager.default.createDirectory(at: tiles, withIntermediateDirectories: true)
        _ = try writeTiles(into: tiles, detector: "insightface")
        let output = root.appendingPathComponent("mixed")

        let summary = try await MixRunner.run(
            input: tiles, output: output, spec: spec, options: options
        )

        #expect(summary.tileCount == 8)
        #expect(summary.compositeCount == 2)
        #expect(summary.writtenCount == 2)
        #expect(summary.unusedCount == 0)
        #expect(summary.frontalityBasis == .yaw, "an insightface run has a usable yaw")

        let files = FileManager.default
        #expect(files.fileExists(atPath: output.appendingPathComponent("mix-0001.psd").path))
        #expect(files.fileExists(atPath: output.appendingPathComponent("mix-0002.psd").path))
        #expect(files.fileExists(atPath: output.appendingPathComponent("mix-manifest.json").path))
        #expect(files.fileExists(atPath: output.appendingPathComponent("mix-report.csv").path))
        #expect(files.fileExists(atPath: output.appendingPathComponent("previews/mix-0001.png").path))

        // Not `manifest.json`: a folder answering to that name is an align run, and both
        // review.sh and ReviewSession would try to open this as one.
        #expect(!files.fileExists(atPath: output.appendingPathComponent("manifest.json").path))
    }

    @Test("the manifest reads back naming every tile exactly once")
    func manifestRoundTrips() async throws {
        let root = try temporary()
        defer { try? FileManager.default.removeItem(at: root) }
        let tiles = root.appendingPathComponent("aligned")
        try FileManager.default.createDirectory(at: tiles, withIntermediateDirectories: true)
        _ = try writeTiles(into: tiles, detector: "insightface")
        let output = root.appendingPathComponent("mixed")

        _ = try await MixRunner.run(input: tiles, output: output, spec: spec, options: options)

        let manifest = try JSONDecoder().decode(
            MixManifest.self,
            from: Data(contentsOf: output.appendingPathComponent("mix-manifest.json"))
        )

        #expect(manifest.canvasSize == 64)
        #expect(manifest.quadrantSize == 32)
        #expect(manifest.seed == 1)
        #expect(manifest.tileCount == 8)
        #expect(manifest.composites.count == 2)
        #expect(manifest.unused.isEmpty)
        #expect(manifest.frontalityBasis == .yaw)
        #expect(!manifest.frontalityNote.isEmpty)
        #expect(manifest.sourceRun == tiles.path)

        let names = manifest.composites.flatMap { $0.quadrants.map(\.name) }
        #expect(names.count == 8)
        #expect(Set(names).count == 8, "a tile was used twice across the batch")

        for composite in manifest.composites {
            #expect(composite.documentPath == String(format: "mix-%04d.psd", composite.index + 1))
            #expect(composite.previewPath != nil)
            #expect(composite.flatPath == nil, "no flat export was asked for")
            #expect(composite.mouthSeam != nil)
            #expect(Set(composite.quadrants.map(\.quadrant)).count == 4)
            for quadrant in composite.quadrants {
                #expect(!quadrant.sourcePath.isEmpty, "the original photograph is named")
                #expect(quadrant.yawDegrees != nil)
            }
        }

        let report = try String(contentsOf: output.appendingPathComponent("mix-report.csv"), encoding: .utf8)
        #expect(report.split(separator: "\n").count == 9, "a header and one row per quadrant")
    }

    @Test("each quadrant of the composite shows the right quarter of the right tile")
    func compositesAreAssembledCorrectly() async throws {
        // The assertion that catches a crop taken from the wrong quarter, or taken upside
        // down — either of which produces a document that opens perfectly happily and is
        // meaningless.
        let root = try temporary()
        defer { try? FileManager.default.removeItem(at: root) }
        let tiles = root.appendingPathComponent("aligned")
        try FileManager.default.createDirectory(at: tiles, withIntermediateDirectories: true)
        _ = try writeTiles(into: tiles, detector: "insightface")
        let output = root.appendingPathComponent("mixed")

        _ = try await MixRunner.run(input: tiles, output: output, spec: spec, options: options)
        let manifest = try JSONDecoder().decode(
            MixManifest.self,
            from: Data(contentsOf: output.appendingPathComponent("mix-manifest.json"))
        )

        let grid = QuadrantGrid(spec: spec)
        for composite in manifest.composites {
            let preview = output.appendingPathComponent(try #require(composite.previewPath))
            let pixels = try Self.pixels(of: preview)

            for record in composite.quadrants {
                let index = try #require(Int(record.name.dropFirst("tile".count)))
                let origin = grid.origin(of: record.quadrant)
                let sample = try #require(pixels.at(
                    x: origin.x + grid.quadrantSize / 2,
                    y: origin.y + grid.quadrantSize / 2
                ))
                #expect(abs(Int(sample.red) - red(forTile: index)) <= 2,
                        "\(record.quadrant) is not from \(record.name)")
                #expect(abs(Int(sample.green) - green(for: record.quadrant)) <= 2,
                        "\(record.quadrant) took the wrong quarter of \(record.name)")
            }
        }
    }

    @Test("a dry run plans the whole batch and writes no documents")
    func dryRun() async throws {
        let root = try temporary()
        defer { try? FileManager.default.removeItem(at: root) }
        let tiles = root.appendingPathComponent("aligned")
        try FileManager.default.createDirectory(at: tiles, withIntermediateDirectories: true)
        _ = try writeTiles(into: tiles, detector: "insightface")
        let output = root.appendingPathComponent("mixed")

        var dry = options
        dry.isDryRun = true
        let summary = try await MixRunner.run(input: tiles, output: output, spec: spec, options: dry)

        #expect(summary.compositeCount == 2)
        #expect(summary.writtenCount == 0)
        #expect(summary.byteCount == 0)
        #expect(!FileManager.default.fileExists(atPath: output.appendingPathComponent("mix-0001.psd").path))

        // The plan is still recorded in full, which is the point: a corpus that would take
        // 19 GB can be looked at before it is committed to.
        let manifest = try JSONDecoder().decode(
            MixManifest.self, from: Data(contentsOf: output.appendingPathComponent("mix-manifest.json"))
        )
        #expect(manifest.composites.count == 2)
        #expect(manifest.composites.allSatisfy { $0.documentPath == nil })
    }

    @Test("a Vision run is not described as pose-sorted")
    func visionRunFallsBackFromYaw() async throws {
        // Vision reports a yaw, but in 45-degree steps — it gave 0 for faces turned 13,
        // 20 and 37. A manifest claiming the top quadrants were chosen on pose would look
        // exactly like one where they were.
        let root = try temporary()
        defer { try? FileManager.default.removeItem(at: root) }
        let tiles = root.appendingPathComponent("aligned")
        try FileManager.default.createDirectory(at: tiles, withIntermediateDirectories: true)
        _ = try writeTiles(into: tiles, detector: "vision")
        let output = root.appendingPathComponent("mixed")

        var dry = options
        dry.isDryRun = true
        let summary = try await MixRunner.run(input: tiles, output: output, spec: spec, options: dry)
        #expect(summary.frontalityBasis == .score)
        #expect(summary.frontalityBasis.explanation.contains("no usable yaw"))
    }

    @Test("a tile the run manifest names but that is not on disk is reported, not skipped")
    func missingTileIsNamed() async throws {
        let root = try temporary()
        defer { try? FileManager.default.removeItem(at: root) }
        let tiles = root.appendingPathComponent("aligned")
        try FileManager.default.createDirectory(at: tiles, withIntermediateDirectories: true)
        let urls = try writeTiles(into: tiles, detector: "insightface")
        // A correction that pushes a tile past a gate removes its file and clears its path
        // — but an older manifest can still name one.
        try FileManager.default.removeItem(at: urls[0])
        let output = root.appendingPathComponent("mixed")

        var dry = options
        dry.isDryRun = true
        let summary = try await MixRunner.run(input: tiles, output: output, spec: spec, options: dry)

        #expect(summary.tileCount == 7)
        #expect(summary.compositeCount == 1)
        #expect(summary.missingTileCount == 1)

        let manifest = try JSONDecoder().decode(
            MixManifest.self, from: Data(contentsOf: output.appendingPathComponent("mix-manifest.json"))
        )
        #expect(manifest.unused.contains { $0.reason.contains("not on disk") })
        #expect(manifest.unused.contains { $0.reason.contains("fewer than four") })
    }

    @Test("a manifest that will not decode stops the run rather than quietly losing the yaw")
    func brokenManifestIsAnError() async throws {
        let root = try temporary()
        defer { try? FileManager.default.removeItem(at: root) }
        let tiles = root.appendingPathComponent("aligned")
        try FileManager.default.createDirectory(at: tiles, withIntermediateDirectories: true)
        _ = try writeTiles(into: tiles, detector: "insightface")
        try Data("{ not json".utf8).write(to: tiles.appendingPathComponent("manifest.json"))

        await #expect(throws: MixCatalogueError.self) {
            _ = try await MixRunner.run(
                input: tiles, output: root.appendingPathComponent("mixed"),
                spec: spec, options: options
            )
        }
    }

    // MARK: Reading a written image back

    struct Pixels {
        let width: Int
        let bytes: [UInt8]

        func at(x: Int, y: Int) -> (red: UInt8, green: UInt8, blue: UInt8)? {
            let index = (y * width + x) * 4
            guard index + 2 < bytes.count else { return nil }
            return (bytes[index], bytes[index + 1], bytes[index + 2])
        }
    }

    static func pixels(of url: URL) throws -> Pixels {
        let image = try ImageLoading.load(url)
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        bytes.withUnsafeMutableBytes { raw in
            let context = CGContext(
                data: raw.baseAddress, width: image.width, height: image.height,
                bitsPerComponent: 8, bytesPerRow: image.width * 4, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
            context?.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        return Pixels(width: image.width, bytes: bytes)
    }
}
