import Foundation
import ProsoponCore

/// The end-of-run report. Written to stdout.
enum Summary {
    static func print(_ tiles: [TileRecord], options: SolveOptions) {
        let accepted = tiles.filter(\.accepted)
        let solved = tiles.compactMap(\.quality)

        var out = "\n"
        out += "  tiles           \(tiles.count) candidate(s), \(accepted.count) accepted\n"

        let failures = tiles.filter { $0.failure != nil }
        if !failures.isEmpty {
            out += "  failed          \(failures.count)\n"
        }

        let counts = Dictionary(grouping: tiles.flatMap(\.rejections), by: { $0 }).mapValues(\.count)
        for reason in RejectionReason.allCases where counts[reason] != nil {
            out += "  rejected        \(counts[reason]!) x \(reason.rawValue)\n"
        }

        if !solved.isEmpty {
            let clamped = solved.filter(\.stretchWasClamped).count
            out += "\n"
            out += "  stretch cap     \(String(format: "%.1f", options.maxStretch * 100))%"
            out += "  ->  \(clamped)/\(solved.count) hit it"
            out += " (\(percent(clamped, of: solved.count)))\n"

            let ratios = tiles.compactMap(\.nativeMouthDropRatio).filter(\.isFinite).sorted()
            if !ratios.isEmpty {
                out += "  native ratio    median \(String(format: "%.3f", median(ratios)))"
                out += ", range \(String(format: "%.3f", ratios.first!))-\(String(format: "%.3f", ratios.last!))"
                out += "  (target 1.125)\n"
            }

            let mouthErrors = solved.map(\.mouthErrorPixels).sorted()
            out += "  mouth error     median \(String(format: "%.1f", median(mouthErrors))) px"
            out += ", worst \(String(format: "%.1f", mouthErrors.last ?? 0)) px\n"

            let magnifications = solved.map(\.magnification).sorted()
            out += "  magnification   median \(String(format: "%.2f", median(magnifications)))x"
            out += ", worst \(String(format: "%.2f", magnifications.last ?? 0))x\n"
        }

        Swift.print(out)
    }

    static func percent(_ part: Int, of whole: Int) -> String {
        guard whole > 0 else { return "0%" }
        return String(format: "%.0f%%", 100 * Double(part) / Double(whole))
    }

    static func median(_ sorted: [Double]) -> Double {
        guard !sorted.isEmpty else { return .nan }
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2)
            ? (sorted[middle - 1] + sorted[middle]) / 2
            : sorted[middle]
    }
}
