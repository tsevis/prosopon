import ArgumentParser
import Foundation
import ProsoponCore
import ProsoponIO
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

    @Flag(name: .long, help: "Also write verification overlays with the grid and target discs.")
    var overlay: Bool = false

    @Option(name: .long, help: "Reject tiles enlarged by more than this factor.")
    var maxMagnification: Double = 2.0

    @Flag(name: .long, help: "Keep tiles that do not fill the whole canvas.")
    var allowPartialCoverage: Bool = false

    @Flag(name: .long, help: "Analyse only; write the manifest but no images.")
    var dryRun: Bool = false

    @Option(name: .long, help: "Resampler: lanczos (GPU), lanczos-cpu, or coregraphics.")
    var resampler: Resampler = .lanczos

    mutating func run() async throws {
        let urls = try shared.resolvedInputs()
        guard let imageFormat = ImageFormat(rawValue: format.lowercased()) else {
            throw ValidationError("unknown format '\(format)'; expected png or tiff")
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
                maxMagnification: maxMagnification
            ),
            selection: shared.faces,
            detector: try shared.makeDetector(),
            renderer: renderer,
            output: dryRun ? nil : OutputPlan(
                directory: outputDirectory,
                overlayDirectory: overlayDirectory,
                format: imageFormat
            )
        )

        FileHandle.standardError.write(Data("Aligning \(urls.count) image(s)\n".utf8))
        let tiles = await BatchRunner.run(
            urls: urls, pipeline: pipeline,
            concurrency: shared.concurrency, showsProgress: true
        )

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
