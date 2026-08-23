import ArgumentParser
import Foundation
import ProsoponCore
import ProsoponIO
import ProsoponPipeline
import ProsoponRender
import ProsoponVision

struct Align: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "align",
        abstract: "Align portraits and write the aligned tiles."
    )

    @OptionGroup var shared: SharedOptions

    @Option(name: .shortAndLong, help: "Directory to write aligned tiles into.")
    var output: String

    @Option(name: .long, help: "Output format: png or tiff.")
    var format: String = "png"

    @Option(name: .long, help: "Bits per channel written: 8 or 16. 16 only pays when the source had more than 8.")
    var bitDepth: Int = 16

    @Flag(name: .long, help: "Also write verification overlays with the grid and target discs.")
    var overlay: Bool = false

    @Option(name: .long, help: "Reject tiles enlarged by more than this factor.")
    var maxMagnification: Double = 2.0

    @Flag(name: .long, help: "Keep tiles that do not fill the whole canvas.")
    var allowPartialCoverage: Bool = false

    @Option(name: .long, help: "Reject faces turned further than this many degrees.")
    var maxYaw: Double = .infinity

    @Flag(name: .long, help: "Analyse only; write the manifest but no images.")
    var dryRun: Bool = false

    @Option(name: .long, help: "Resampler: lanczos (GPU), lanczos-cpu, or coregraphics.")
    var resampler: Resampler = .lanczos

    mutating func run() async throws {
        let urls = try shared.resolvedInputs()
        guard let imageFormat = ImageFormat(rawValue: format.lowercased()) else {
            throw ValidationError("unknown format '\(format)'; expected png or tiff")
        }
        guard let depth = OutputDepth(rawValue: bitDepth) else {
            throw ValidationError("bit depth must be 8 or 16")
        }

        let outputDirectory = URL(fileURLWithPath: (output as NSString).expandingTildeInPath)
        let overlayDirectory = overlay ? outputDirectory.appendingPathComponent("overlays") : nil
        if !dryRun {
            try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
            if let overlayDirectory {
                try FileManager.default.createDirectory(at: overlayDirectory, withIntermediateDirectories: true)
            }
        }

        let spec = CanvasSpec.standard
        // Built once and shared: compiling the shader and creating the queue is a
        // per-process cost, not a per-image one.
        let renderer = try resampler.makeRenderer(spec: spec)
        let pipeline = Pipeline(
            spec: spec,
            solveOptions: shared.solveOptions,
            thresholds: QualityThresholds(
                requiresFullCoverage: !allowPartialCoverage,
                maxMagnification: maxMagnification,
                maxYawDegrees: maxYaw
            ),
            selection: shared.faces,
            detector: try shared.makeDetector(),
            renderer: renderer,
            output: dryRun ? nil : OutputPlan(
                directory: outputDirectory,
                overlayDirectory: overlayDirectory,
                format: imageFormat,
                depth: depth
            )
        )

        // Vision reports yaw in 45-degree steps, so a gate set against it would pass a
        // face turned 36 degrees as though it were frontal. Better to say so than to let
        // the flag look like it is doing something.
        if maxYaw.isFinite && shared.detector == .vision {
            let warning = "warning: --max-yaw does little with the vision detector, which reports"
                + " yaw only in 45 degree steps. On a six-face photograph it gave 0 degrees for"
                + " faces turned 13, 20 and 37 degrees. Use --detector insightface for a gate"
                + " that means something.\n"
            FileHandle.standardError.write(Data(warning.utf8))
        }

        FileHandle.standardError.write(Data("Aligning \(urls.count) image(s)\n".utf8))
        let tiles = await BatchRunner.run(
            urls: urls, pipeline: pipeline,
            concurrency: shared.concurrency, onProgress: ProgressBar.draw
        )
        ProgressBar.finish()

        if !dryRun {
            try writeManifest(tiles, spec: spec, to: outputDirectory)
        }
        Summary.print(tiles, options: shared.solveOptions)
    }

    private func writeManifest(_ tiles: [TileRecord], spec: CanvasSpec, to directory: URL) throws {
        let manifest = RunManifest(
            canvasSize: spec.size,
            gridStep: spec.gridStep,
            targets: [
                "viewerLeftEye": spec.viewerLeftEye,
                "viewerRightEye": spec.viewerRightEye,
                "mouth": spec.mouth,
            ],
            maxStretch: shared.maxStretch,
            maxShear: shared.noShear ? 0 : shared.maxShear,
            detector: shared.detector.rawValue,
            resampler: resampler.rawValue,
            tiles: tiles
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(manifest).write(to: directory.appendingPathComponent("manifest.json"))
        try Data(CSVReport.render(tiles).utf8).write(to: directory.appendingPathComponent("report.csv"))
    }
}
