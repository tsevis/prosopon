import ArgumentParser
import Foundation
import ProsoponCore
import ProsoponPipeline
import ProsoponRender
import ProsoponVision

/// Measures the corpus against the fixed canvas without writing anything.
///
/// The target proportion, mouth drop over interocular distance, is 1.125. Real faces
/// cluster somewhere below that, so a portion of any corpus will demand more than the
/// 5 percent stretch budget and land its mouth high. The coordinates are fixed, so this
/// is not a decision to be made — but it is worth knowing the size of the effect before
/// judging output, and it says immediately how much of the corpus is usable at all.
struct Calibrate: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "calibrate",
        abstract: "Report how a corpus of portraits sits against the fixed canvas."
    )

    @OptionGroup var shared: SharedOptions

    @Option(name: .long, help: "Write the per-image measurements to this CSV.")
    var csv: String?

    mutating func run() async throws {
        let urls = try shared.resolvedInputs()

        let pipeline = Pipeline(
            spec: .standard,
            solveOptions: shared.solveOptions,
            thresholds: QualityThresholds(requiresFullCoverage: true, maxMagnification: .infinity),
            selection: shared.faces,
            detector: try shared.makeDetector(),
            renderer: CoreGraphicsRenderer(spec: .standard),   // never used: output is nil
            output: nil
        )

        FileHandle.standardError.write(Data("Measuring \(urls.count) image(s)\n".utf8))
        let tiles = await BatchRunner.run(
            urls: urls, pipeline: pipeline,
            concurrency: shared.concurrency, onProgress: ProgressBar.draw
        )
        ProgressBar.finish()

        if let csv {
            let url = URL(fileURLWithPath: (csv as NSString).expandingTildeInPath)
            try Data(CSVReport.render(tiles).utf8).write(to: url)
            FileHandle.standardError.write(Data("wrote \(url.path)\n".utf8))
        }

        Summary.print(tiles, options: shared.solveOptions)
        printRatioHistogram(tiles)
    }

    private func printRatioHistogram(_ tiles: [TileRecord]) {
        let ratios = tiles.compactMap(\.nativeMouthDropRatio).filter(\.isFinite).sorted()
        guard ratios.count > 1 else { return }

        let buckets = stride(from: 0.85, to: 1.35, by: 0.05).map { lower in
            (lower, ratios.filter { $0 >= lower && $0 < lower + 0.05 }.count)
        }
        let peak = max(1, buckets.map(\.1).max() ?? 1)

        print("  native mouth-drop ratio (target 1.125)\n")
        for (lower, count) in buckets where count > 0 || (lower > 0.95 && lower < 1.25) {
            let bar = String(repeating: "#", count: Int((Double(count) / Double(peak)) * 40))
            let marker = (lower <= 1.125 && 1.125 < lower + 0.05) ? " <- target" : ""
            print(String(format: "  %.2f  %-40@ %3d%@", lower, bar as NSString, count, marker))
        }
        print("")
    }
}
