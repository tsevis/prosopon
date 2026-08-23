import Foundation
import ProsoponCore

/// The manifest, flattened for sorting in a spreadsheet. Reviewing hundreds of tiles
/// means sorting by score and looking at the worst twenty; CSV is the shortest path there.
public enum CSVReport {
    public static let header = [
        "source", "face", "accepted", "rejections", "score",
        "coverage_pct", "magnification", "mouth_error_px",
        "stretch_applied_pct", "stretch_wanted_pct", "stretch_clamped",
        "shear_clamped", "roll_deg", "yaw_deg", "pose_yaw_deg", "native_ratio", "output", "failure",
    ]

    public static func render(_ tiles: [TileRecord]) -> String {
        var lines = [header.joined(separator: ",")]
        for tile in tiles {
            let quality = tile.quality
            let fields: [String] = [
                tile.sourcePath,
                String(tile.faceIndex),
                tile.accepted ? "yes" : "no",
                tile.rejections.map(\.rawValue).joined(separator: " "),
                format(quality?.score, decimals: 4),
                format(quality.map { $0.coverage * 100 }, decimals: 2),
                format(quality?.magnification, decimals: 4),
                format(quality?.mouthErrorPixels, decimals: 2),
                format(quality?.appliedStretchPercent, decimals: 2),
                format(quality?.requestedStretchPercent, decimals: 2),
                quality.map { $0.stretchWasClamped ? "yes" : "no" } ?? "",
                quality.map { $0.shearWasClamped ? "yes" : "no" } ?? "",
                format(quality?.rollCorrectionDegrees, decimals: 2),
                format(tile.yawDegrees, decimals: 2),
                format(quality?.yawDegrees, decimals: 2),
                format(tile.nativeMouthDropRatio, decimals: 4),
                tile.outputPath ?? "",
                tile.failure ?? "",
            ]
            lines.append(fields.map(escape).joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func format(_ value: Double?, decimals: Int) -> String {
        guard let value, value.isFinite else { return "" }
        return String(format: "%.\(decimals)f", value)
    }

    private static func escape(_ field: String) -> String {
        guard field.contains(",") || field.contains("\"") || field.contains("\n") else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
