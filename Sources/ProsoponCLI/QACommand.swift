import ArgumentParser
import CoreGraphics
import Foundation
import ProsoponCore
import ProsoponIO
import ProsoponQA
import ProsoponRender

struct QA: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "qa",
        abstract: "Average an aligned stack and report how well it registered.",
        discussion: """
            Superimposing hundreds of aligned faces should leave the eyes and mouth crisp \
            while everything that varies between people averages into a blur. One image \
            says whether a whole batch is usable.

            Alignment is solved analytically and puts the eyes on target to within a \
            billionth of a pixel, so a soft average never means the arithmetic slipped -- \
            it means the landmark detector was wrong on some tiles. Each tile is therefore \
            also measured against the stack's consensus, turning "the average looks soft" \
            into a ranked list of files to look at.
            """
    )

    @Argument(help: "Aligned tiles, or directories of them.")
    var inputs: [String]

    @Option(name: .shortAndLong, help: "Directory to write the QA images and reports into.")
    var output: String

    @Option(name: .long, help: "Call out tiles further than this many pixels from consensus.")
    var suspectThreshold: Double = 2

    @Option(name: .long, help: "How many tiles to put on the contact sheet.")
    var contactSheetCount: Int = 24

    @Option(name: .long, help: "Brightness multiplier for the deviation image.")
    var deviationGain: Double = 3

    mutating func run() async throws {
        let tiles = try resolveTiles()
        let spec = CanvasSpec.standard
        let directory = URL(fileURLWithPath: (output as NSString).expandingTildeInPath)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        FileHandle.standardError.write(Data("Averaging \(tiles.count) tile(s)\n".utf8))
        let result = try await MeanFaceBuilder.analyse(
            tiles: tiles,
            options: QAOptions(spec: spec, deviationGain: deviationGain, suspectThreshold: suspectThreshold)
        ) { done, total in
            FileHandle.standardError.write(Data("\r  \(done)/\(total)".utf8))
        }
        FileHandle.standardError.write(Data("\n".utf8))

        try write(result, spec: spec, to: directory)
        report(result.report, threshold: suspectThreshold, directory: directory)
    }

    private func resolveTiles() throws -> [URL] {
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
        return urls
    }

    private func write(_ result: QAResult, spec: CanvasSpec, to directory: URL) throws {
        if let mean = result.mean.makeCGImage() {
            try ImageWriting.write(mean, to: directory.appendingPathComponent("mean.png"), format: .png)
            if let overlaid = OverlayRenderer(spec: spec).draw(over: mean) {
                try ImageWriting.write(
                    overlaid, to: directory.appendingPathComponent("mean-overlay.png"), format: .png
                )
            }
        }
        // Tagged sRGB rather than linear: these are sigma values, and applying a
        // transfer function to them would make `--deviation-gain` a lie.
        if let deviation = result.deviation.makeCGImage(colorSpace: CGColorSpace(name: CGColorSpace.sRGB)) {
            try ImageWriting.write(
                deviation, to: directory.appendingPathComponent("deviation.png"), format: .png
            )
        }

        let worst = Array(
            result.report.tiles.sorted { $0.worstDisplacement > $1.worstDisplacement }
                .prefix(max(0, contactSheetCount))
        )
        if let sheet = try ContactSheet.render(tiles: worst, spec: spec) {
            try ImageWriting.write(
                sheet, to: directory.appendingPathComponent("contact-sheet.png"), format: .png
            )
        }

        try Data(QAReport.csv(result.report).utf8)
            .write(to: directory.appendingPathComponent("qa.csv"))

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(result.report).write(to: directory.appendingPathComponent("qa.json"))
    }

    private func report(_ report: StackQA, threshold: Double, directory: URL) {
        var out = "\n"
        out += "  tiles              \(report.tileCount)\n\n"

        out += "  sharpness retained by the average\n"
        for landmark in Landmark.allCases {
            guard let sharpness = report.landmarkSharpness[landmark] else { continue }
            out += String(format: "    %-8@ %.3f\n", landmark.shortName as NSString, sharpness.retention)
        }
        out += String(format: "    %-8@ %.3f\n", "overall" as NSString, report.globalSharpness.retention)
        out += String(format: "    contrast %.2fx", report.registrationContrast)
        out += "   (landmarks against the whole canvas; above 1 means they survived averaging better)\n"

        let displacements = report.displacements
        if !displacements.isEmpty {
            out += "\n  distance from consensus\n"
            out += String(format: "    median   %.2f px\n", report.percentile(0.5))
            out += String(format: "    90th     %.2f px\n", report.percentile(0.9))
            out += String(format: "    worst    %.2f px\n", displacements.last ?? 0)
        }

        let suspects = report.suspects(beyond: threshold)
        out += String(format: "\n  beyond %.1f px      %d of %d tiles\n",
                      threshold, suspects.count, report.tileCount)
        for tile in suspects.prefix(10) {
            let clipped = tile.anyClipped ? "  (at least; past the search window)" : ""
            out += String(format: "    %-28@ %5.2f px at the %-6@ match %.2f%@\n",
                          tile.name as NSString, tile.worstDisplacement,
                          (tile.worstLandmark?.shortName ?? "-") as NSString,
                          tile.lowestCorrelation, clipped as NSString)
        }
        if suspects.count > 10 {
            out += "    ... \(suspects.count - 10) more in qa.csv\n"
        }

        let unmatched = report.unmatched()
        if !unmatched.isEmpty {
            out += "\n  could not be matched   \(unmatched.count) of \(report.tileCount)\n"
            out += "    the landmark was not found near where it should be, so no displacement\n"
            out += "    is reported. A mirrored face, an unusual pose, or a bad detection.\n"
            for tile in unmatched.prefix(10) {
                out += String(format: "    %-28@ match %.2f\n",
                              tile.name as NSString, tile.lowestCorrelation)
            }
        }

        out += "\n  wrote mean.png, mean-overlay.png, deviation.png, contact-sheet.png,"
        out += " qa.csv and qa.json to \(directory.path)\n"
        print(out)
    }
}

enum QAReport {
    static func csv(_ report: StackQA) -> String {
        var header = ["tile", "worst_px", "worst_landmark"]
        for landmark in Landmark.allCases {
            header += ["\(landmark.rawValue)_dx", "\(landmark.rawValue)_dy",
                       "\(landmark.rawValue)_px", "\(landmark.rawValue)_ncc"]
        }
        header.append("clipped")
        header.append("path")

        var lines = [header.joined(separator: ",")]
        for tile in report.tiles.sorted(by: { $0.worstDisplacement > $1.worstDisplacement }) {
            var fields = [
                tile.name,
                String(format: "%.3f", tile.worstDisplacement),
                tile.worstLandmark?.rawValue ?? "",
            ]
            for landmark in Landmark.allCases {
                let offset = tile.offsets[landmark] ?? .none
                fields += [
                    String(format: "%.3f", offset.dx),
                    String(format: "%.3f", offset.dy),
                    String(format: "%.3f", offset.magnitude),
                    String(format: "%.4f", offset.correlation),
                ]
            }
            fields.append(tile.anyClipped ? "yes" : "no")
            fields.append(tile.path)
            lines.append(fields.map(escape).joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func escape(_ field: String) -> String {
        guard field.contains(",") || field.contains("\"") else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
