import ArgumentParser
import Foundation
import ProsoponCore
import ProsoponIO
import ProsoponMix
import ProsoponPSD

struct Mix: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "mix",
        abstract: "Compose aligned tiles into quartered portraits.",
        discussion: """
            Each output is one 2048 x 2048 canvas divided into four 1024 x 1024 quadrants, \
            every quadrant from a different photograph. N tiles in, N/4 documents out, \
            with each image used exactly once in the whole batch.

            The quadrant seams fall at x = 1024 and y = 1024, which puts each eye well \
            inside a top quadrant and the mouth exactly on the vertical seam — so the two \
            bottom quadrants carry half a mouth each, from two different people. That is \
            the hardest join in the picture and it is what the matching spends its first \
            choice on: candidates are scored on the tone of a narrow strip either side of \
            the seam, with the mouth band weighted several times the rest of it, then on \
            the cheeks and the nose bridge. The most frontal half of the corpus is \
            reserved for the two top quadrants, where the eyes are.

            Quadrants are positioned layers, not masked full-canvas ones: about a quarter \
            of the file size, and no way to slide a seam in Photoshop afterwards. \
            Regenerate with a different --seed instead.

            A composite is roughly 30 MB, so a few hundred is several gigabytes. Use \
            --dry-run to see the plan and the manifest first, or --limit to write a few.
            """
    )

    @Argument(help: "A run directory written by `prosopon align`, or a folder of aligned tiles.")
    var input: String

    @Option(name: .shortAndLong, help: "Directory to write the composites into.")
    var output: String

    @Option(name: .long, help: "Seeds the shuffle and every fallback pick, so a run reproduces.")
    var seed: UInt64 = 1

    @Option(name: .long, help: "Width of the seam strip that tones are matched on, in canvas pixels.")
    var seamWidth: Int = 16

    @Option(name: .long, help: "Height of the mouth band, centred on the mouth target.")
    var mouthBand: Int = 384

    @Option(name: .long, help: "Resolution tiles are decoded at for measurement.")
    var measureSize: Int = 1024

    @Option(name: .long, help: "Container: psd (a composite is far inside its 2 GB) or psb.")
    var format: DocumentFormat = .psd

    @Option(name: .long, help: "Bits per channel: 8 or 16.")
    var bitDepth: Int = 8

    @Option(name: .long, help: "Channel compression: rle or raw.")
    var compression: Compression = .rle

    @Option(name: .long, help: "Resolution recorded in the document.")
    var dpi: Double = 72

    @Flag(name: .long, help: "Leave out the three hidden landmark markers.")
    var noMarkers: Bool = false

    @Flag(name: .long, help: "Leave out the white background layer.")
    var noBackground: Bool = false

    @Option(name: .long, help: "Size of the flattened preview written beside each document. 0 for none.")
    var previewSize: Int = 512

    @Option(name: .long, help: "Also write a full-size flattened export: png or tiff.")
    var flat: String?

    @Option(name: .long, help: "Write only the first N composites. The plan still covers everything.")
    var limit: Int?

    @Flag(name: .long, help: "Plan and write the manifest, write no documents.")
    var dryRun: Bool = false

    @Option(name: .long, help: "Concurrent composites. Defaults to the core count.")
    var jobs: Int?

    mutating func run() async throws {
        guard let depth = BitDepth(rawValue: bitDepth) else {
            throw ValidationError("bit depth must be 8 or 16")
        }
        guard seamWidth > 0 else { throw ValidationError("seam width must be at least 1") }
        guard mouthBand > 0 else { throw ValidationError("mouth band must be at least 1") }
        if let limit, limit < 1 { throw ValidationError("limit must be at least 1") }

        let flatFormat: ImageFormat?
        if let flat {
            guard let parsed = ImageFormat(rawValue: flat.lowercased()) else {
                throw ValidationError("unknown flat format '\(flat)'; expected png or tiff")
            }
            flatFormat = parsed
        } else {
            flatFormat = nil
        }

        let inputURL = URL(fileURLWithPath: (input as NSString).expandingTildeInPath)
        let outputURL = URL(fileURLWithPath: (output as NSString).expandingTildeInPath)

        let options = MixOptions(
            seed: seed,
            seamWidth: seamWidth,
            mouthBandHeight: mouthBand,
            measureSize: measureSize,
            format: format,
            depth: depth,
            compression: compression,
            dpi: dpi,
            includesMarkers: !noMarkers,
            includesBackground: !noBackground,
            previewSize: previewSize > 0 ? previewSize : nil,
            flatFormat: flatFormat,
            limit: limit,
            isDryRun: dryRun,
            concurrency: jobs ?? max(1, ProcessInfo.processInfo.activeProcessorCount)
        )

        let summary = try await MixRunner.run(
            input: inputURL, output: outputURL, spec: .standard, options: options,
            onProgress: MixProgress.draw
        )
        MixProgress.finish()
        report(summary, options: options)
    }

    private func report(_ summary: MixSummary, options: MixOptions) {
        var out = "\n"
        out += "  tiles           \(summary.tileCount) aligned\n"
        out += "  composites      \(summary.compositeCount) planned"
        out += summary.writtenCount == summary.compositeCount
            ? ", all written\n"
            : ", \(summary.writtenCount) written\n"

        if summary.unusedCount > 0 {
            // Named rather than passed over: losing four photographs from a batch without
            // being told is not a good way to find out.
            out += "  left over       \(summary.unusedCount)"
            out += " (a composite needs exactly four; they are named in the manifest)\n"
        }
        if summary.missingTileCount > 0 {
            out += "  missing tiles   \(summary.missingTileCount)"
            out += " named in the run manifest but not on disk\n"
        }

        out += "  top quadrants   \(summary.frontalityBasis.explanation)\n"
        out += "  seed            \(options.seed)\n"

        if summary.byteCount > 0 {
            let gigabytes = Double(summary.byteCount) / Double(1 << 30)
            out += String(format: "  written         %.2f GB\n", gigabytes)
        }
        out += "  manifest        \(summary.manifestURL.path)\n"
        print(out)
    }
}

/// The mix's two phases, drawn on stderr so stdout stays clean for piping.
enum MixProgress {
    private static let width = 28

    static let draw: @Sendable (MixRunner.Progress) -> Void = { progress in
        let filled = Int(Double(width) * progress.fraction)
        let bar = String(repeating: "#", count: filled)
            + String(repeating: ".", count: width - filled)
        let label = progress.phase == .measuring ? "measuring" : "composing"
        FileHandle.standardError.write(
            Data("\r  \(label) [\(bar)] \(progress.completed)/\(progress.total)".utf8)
        )
        if progress.completed == progress.total {
            FileHandle.standardError.write(Data("\n".utf8))
        }
    }

    static func finish() {}
}
