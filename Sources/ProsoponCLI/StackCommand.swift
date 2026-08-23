import ArgumentParser
import Foundation
import ProsoponIO
import ProsoponPSD

struct Stack: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "stack",
        abstract: "Collect aligned tiles into a layered Photoshop document.",
        discussion: """
            Takes the tiles produced by `align` and writes them as one layered document, \
            first file on top. Because the tiles all sit on the same 2048 x 2048 grid, \
            any fragment of any layer lines up with the same fragment of every other.

            A 2048 x 2048 RGBA layer costs about 16 MB at 8-bit and photographic data \
            barely compresses, so a few hundred layers pass the 2 GB ceiling that .psd \
            cannot express. That is why .psb is the default; use --batch-size to split \
            a large corpus into several documents instead.
            """
    )

    @Argument(help: "Aligned tiles, or directories of them.")
    var inputs: [String]

    @Option(name: .shortAndLong, help: "Output document path.")
    var output: String

    @Option(name: .long, help: "Container: psb (no practical size limit) or psd (2 GB).")
    var format: DocumentFormat = .psb

    @Option(name: .long, help: "Bits per channel: 8 or 16.")
    var bitDepth: Int = 8

    @Option(name: .long, help: "Channel compression: rle or raw.")
    var compression: Compression = .rle

    @Option(name: .long, help: "Resolution recorded in the document.")
    var dpi: Double = 72

    @Option(name: .long, help: "Split into several documents of at most this many layers.")
    var batchSize: Int?

    mutating func run() async throws {
        guard let depth = BitDepth(rawValue: bitDepth) else {
            throw ValidationError("bit depth must be 8 or 16")
        }
        if let batchSize, batchSize < 1 {
            throw ValidationError("batch size must be at least 1")
        }

        let tiles = try resolveTiles()
        let options = StackOptions(format: format, depth: depth, compression: compression, dpi: dpi)
        let destination = URL(fileURLWithPath: (output as NSString).expandingTildeInPath)
        let batches = split(tiles, by: batchSize)

        FileHandle.standardError.write(Data(
            "Stacking \(tiles.count) tile(s) into \(batches.count) document(s)\n".utf8
        ))

        var summaries: [StackSummary] = []
        for (index, batch) in batches.enumerated() {
            let url = batches.count == 1 ? destination : numbered(destination, index: index + 1)
            let summary = try StackWriter.write(layers: batch, to: url, options: options) { done, total in
                let overall = batches.count == 1 ? "" : " [\(index + 1)/\(batches.count)]"
                let footprint = Diagnostics.residentMegabytes.map { ", \($0) MB resident" } ?? ""
                FileHandle.standardError.write(Data("\r  \(done)/\(total) layers\(overall)\(footprint)".utf8))
            }
            FileHandle.standardError.write(Data("\n".utf8))
            summaries.append(summary)
        }

        report(summaries, options: options)
    }

    private func resolveTiles() throws -> [StackLayer] {
        var urls: [URL] = []
        for input in inputs {
            let url = URL(fileURLWithPath: (input as NSString).expandingTildeInPath)
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
                throw ValidationError("no such file or directory: \(input)")
            }
            if isDirectory.boolValue {
                urls.append(contentsOf: try ImageLoading.imageURLs(in: url))
            } else {
                urls.append(url)
            }
        }
        guard !urls.isEmpty else { throw ValidationError("no tiles found in the given inputs") }
        return urls.map(StackLayer.init(url:))
    }

    private func split(_ tiles: [StackLayer], by size: Int?) -> [[StackLayer]] {
        guard let size, size < tiles.count else { return [tiles] }
        return stride(from: 0, to: tiles.count, by: size).map {
            Array(tiles[$0..<min($0 + size, tiles.count)])
        }
    }

    private func numbered(_ url: URL, index: Int) -> URL {
        let ext = url.pathExtension
        let stem = url.deletingPathExtension().lastPathComponent
        return url.deletingLastPathComponent()
            .appendingPathComponent(String(format: "%@_%03d.%@", stem, index, ext))
    }

    private func report(_ summaries: [StackSummary], options: StackOptions) {
        var out = "\n"
        for summary in summaries {
            let megabytes = Double(summary.byteCount) / Double(1 << 20)
            out += String(
                format: "  %@  %d layers, %dx%d, %.0f-bit, %.1f MB\n",
                summary.url.lastPathComponent, summary.layerCount,
                summary.width, summary.height,
                Double(options.depth.rawValue), megabytes
            )
        }
        if summaries.count > 1 {
            let total = summaries.reduce(0.0) { $0 + Double($1.byteCount) / Double(1 << 30) }
            out += String(format: "\n  %d documents, %.2f GB total\n", summaries.count, total)
        }
        print(out)
    }
}

extension DocumentFormat: ExpressibleByArgument {}
extension Compression: ExpressibleByArgument {}


