import Foundation
import ProsoponCore

/// Writes what a run leaves behind: `manifest.json` and `report.csv`.
///
/// Shared rather than duplicated, so a folder written by the app and a folder written by
/// `prosopon align` are the same folder. A run that carried a manifest from one surface
/// and not a report from the other would be a difference nobody could see until `qa` or
/// the review app went looking for something that was not there.
public enum RunWriter {

    public static func write(
        _ tiles: [TileRecord],
        to directory: URL,
        spec: CanvasSpec,
        solveOptions: SolveOptions,
        detector: String,
        resampler: String
    ) throws {
        let manifest = RunManifest(
            canvasSize: spec.size,
            gridStep: spec.gridStep,
            targets: [
                "viewerLeftEye": spec.viewerLeftEye,
                "viewerRightEye": spec.viewerRightEye,
                "mouth": spec.mouth,
            ],
            maxStretch: solveOptions.maxStretch,
            // A run made with shear turned off records a maximum of zero rather than the
            // number it was told to ignore, so reopening it solves the way it was solved.
            maxShear: solveOptions.correctsHorizontalMouthOffset ? solveOptions.maxShear : 0,
            detector: detector,
            resampler: resampler,
            tiles: tiles
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(manifest).write(to: directory.appendingPathComponent("manifest.json"))
        try Data(CSVReport.render(tiles).utf8)
            .write(to: directory.appendingPathComponent("report.csv"))
    }
}
