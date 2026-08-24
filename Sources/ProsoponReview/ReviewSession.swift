import Foundation
import Observation
import ProsoponCore
import ProsoponIO
import ProsoponQA

public enum ReviewSortOrder: String, CaseIterable, Sendable {
    /// Worst first. The point of the app is the handful the detector got wrong.
    case triage
    /// By how far the tile sat from the stack consensus, when a QA run has been read.
    case consensus
    case name

    public var label: String {
        switch self {
        case .triage: "Needs attention"
        case .consensus: "Distance from consensus"
        case .name: "Name"
        }
    }
}

public enum ReviewLoadError: Error, CustomStringConvertible {
    case noManifest(URL)
    case unreadableManifest(URL, String)
    case emptyManifest(URL)

    public var description: String {
        switch self {
        case .noManifest(let url):
            "no manifest.json in \(url.path). Run `prosopon align` first."
        case .unreadableManifest(let url, let reason):
            "could not read \(url.lastPathComponent): \(reason)"
        case .emptyManifest(let url):
            "\(url.lastPathComponent) lists no tiles"
        }
    }
}

/// The whole review: what was loaded, what is selected, and what has been corrected.
@MainActor
@Observable
public final class ReviewSession {
    public private(set) var directory: URL
    public private(set) var entries: [ReviewEntry] = []
    public private(set) var spec: CanvasSpec = .standard
    public private(set) var options: SolveOptions = .default
    public private(set) var resampler: String = "lanczos"
    public private(set) var detector: String = "vision"
    /// The gates the run was aligned with, so re-solving a correction reaches the same
    /// verdict the run did rather than the built-in defaults'.
    public private(set) var thresholds: QualityThresholds = .default
    /// Bits per channel the run's tiles were written at, so a correction re-renders at
    /// the depth the rest of the folder is in.
    public private(set) var bitDepth: Int = 16

    public var sortOrder: ReviewSortOrder = .triage {
        didSet { applySort() }
    }
    public var selection: ReviewEntry.ID?
    public private(set) var lastSaveSummary: String?
    /// True when a QA report was found and read, so the consensus ordering means something.
    public private(set) var loadedQAReport = false
    /// Set when a report was present but unreadable, rather than letting it pass unnoticed.
    public private(set) var qaReportProblem: String?

    /// Whether this folder is a run, asked before opening rather than by opening and
    /// catching the failure. Lets a caller handed an arbitrary folder tell the two kinds
    /// apart — a run to review, or portraits to import — instead of assuming.
    public static func isRun(_ directory: URL) -> Bool {
        FileManager.default.fileExists(
            atPath: directory.appendingPathComponent("manifest.json").path
        )
    }

    public init(directory: URL) throws {
        self.directory = directory
        try load()
    }

    /// Reads `manifest.json`, and `qa.json` alongside it when a QA run has been done.
    private func load() throws {
        let manifestURL = directory.appendingPathComponent("manifest.json")
        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            throw ReviewLoadError.noManifest(directory)
        }

        let manifest: RunManifest
        do {
            manifest = try JSONDecoder().decode(RunManifest.self, from: Data(contentsOf: manifestURL))
        } catch {
            throw ReviewLoadError.unreadableManifest(manifestURL, "\(error)")
        }

        spec = CanvasSpec.standard.scaled(toSize: manifest.canvasSize)
        options = SolveOptions(
            maxStretch: manifest.maxStretch,
            maxShear: manifest.maxShear,
            correctsHorizontalMouthOffset: manifest.maxShear > 0
        )
        resampler = manifest.resampler
        detector = manifest.detector
        thresholds = manifest.thresholds
        bitDepth = manifest.bitDepth

        entries = manifest.tiles.compactMap { record in
            guard let landmarks = record.landmarks else { return nil }
            return ReviewEntry(
                id: "\(record.sourcePath)#\(record.faceIndex)",
                sourceURL: URL(fileURLWithPath: record.sourcePath),
                outputURL: record.outputPath.map { URL(fileURLWithPath: $0) },
                faceIndex: record.faceIndex,
                sourceWidth: record.sourceWidth,
                sourceHeight: record.sourceHeight,
                detected: landmarks,
                detectedYawDegrees: record.yawDegrees,
                spec: spec,
                options: options,
                thresholds: thresholds
            )
        }
        guard !entries.isEmpty else { throw ReviewLoadError.emptyManifest(manifestURL) }

        mergeQAReport()
        applySort()
        selection = entries.first?.id
    }

    /// Folds in `qa.json` when it is there, so the ordering can follow the consensus
    /// measurement rather than the per-tile score alone.
    ///
    /// Decoded as the very type the QA pass writes. An earlier version declared its own
    /// private copy of the schema, on the theory that a partial report should not fail
    /// the load; what it actually bought was a silent, permanent one — the two drifted,
    /// every decode failed, and the ordering this feeds simply never worked. A missing
    /// file is still fine; a malformed one is now worth saying out loud.
    private func mergeQAReport() {
        guard let url = Self.locateQAReport(near: directory),
              let data = try? Data(contentsOf: url)
        else { return }

        let report: StackQA
        do {
            report = try JSONDecoder().decode(StackQA.self, from: data)
        } catch {
            qaReportProblem = "\(url.lastPathComponent) could not be read: \(error)"
            return
        }

        var byName: [String: TileQA] = [:]
        for tile in report.tiles { byName[tile.name] = tile }

        for index in entries.indices {
            let key = entries[index].outputURL?.deletingPathExtension().lastPathComponent
                ?? entries[index].name
            guard let tile = byName[key] else { continue }
            entries[index].consensusDisplacement = tile.worstDisplacement
            entries[index].consensusMatched = tile.lowestCorrelation >= StackQA.matchFloor
        }
        loadedQAReport = true
    }

    /// Where a QA report might sit relative to the run it describes.
    ///
    /// `prosopon qa` takes its own output directory, so the report is usually *not*
    /// beside the manifest. Looking only there meant the consensus ordering never
    /// engaged for anyone who followed the documented commands.
    static func locateQAReport(near directory: URL) -> URL? {
        let candidates = [
            directory.appendingPathComponent("qa.json"),
            directory.appendingPathComponent("qa").appendingPathComponent("qa.json"),
            directory.deletingLastPathComponent()
                .appendingPathComponent("qa").appendingPathComponent("qa.json"),
        ]
        return candidates.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    // MARK: Ordering and selection

    private func applySort() {
        switch sortOrder {
        case .triage:
            entries.sort { $0.triageRank < $1.triageRank }
        case .consensus:
            entries.sort {
                // Unmatched tiles first: they need a decision, not a measurement.
                let left = $0.consensusMatched == false ? Double.infinity : ($0.consensusDisplacement ?? -1)
                let right = $1.consensusMatched == false ? Double.infinity : ($1.consensusDisplacement ?? -1)
                return left > right
            }
        case .name:
            entries.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }
    }

    public var selected: ReviewEntry? {
        guard let selection else { return nil }
        return entries.first { $0.id == selection }
    }

    public var selectedIndex: Int? {
        guard let selection else { return nil }
        return entries.firstIndex { $0.id == selection }
    }

    public func selectNext() { move(by: 1) }
    public func selectPrevious() { move(by: -1) }

    private func move(by delta: Int) {
        guard !entries.isEmpty else { return }
        let current = selectedIndex ?? 0
        selection = entries[min(max(current + delta, 0), entries.count - 1)].id
    }

    // MARK: Editing

    public func moveLandmark(_ which: Landmark, toCanvasPoint point: Point2D) {
        guard let index = selectedIndex else { return }
        entries[index].setLandmark(which, toCanvasPoint: point, spec: spec, options: options)
    }

    /// The same correction stated in source space, which is where a landmark actually
    /// lives. The drag says it in canvas space; a test can say it directly.
    public func moveLandmark(_ which: Landmark, toSourcePoint point: Point2D) {
        guard let index = selectedIndex else { return }
        entries[index].setLandmark(which, toSourcePoint: point, spec: spec, options: options)
    }

    /// The solve that *would* result from putting `which` at `point`, without committing.
    ///
    /// Lets the metrics track a drag in progress while the rendered image stays put, so
    /// the reviewer can see the mouth error fall before deciding to let go.
    public func prospectiveEntry(_ which: Landmark, atCanvasPoint point: Point2D) -> ReviewEntry? {
        guard var entry = selected else { return nil }
        entry.setLandmark(which, toCanvasPoint: point, spec: spec, options: options)
        return entry
    }

    public func revertSelected() {
        guard let index = selectedIndex else { return }
        entries[index].revert(spec: spec, options: options)
    }

    public func revertAll() {
        for index in entries.indices { entries[index].revert(spec: spec, options: options) }
    }

    public var editedEntries: [ReviewEntry] { entries.filter(\.isEdited) }
    public var editCount: Int { editedEntries.count }

    public func recordSave(_ summary: String) { lastSaveSummary = summary }

    /// Tiles that differ from what the detector found, saved or not. Revert acts on these.
    public var correctedCount: Int { entries.count(where: \.isCorrected) }

    /// Records which tiles are now on disk, and in what state.
    ///
    /// Without this the edit count could never fall: `isEdited` used to mean "differs from
    /// the detector", which stays true after a correction is written. The banner claimed
    /// unsaved work for ever and Save stayed lit over a save that had in fact worked.
    public func markSaved(_ written: [String: FaceLandmarks]) {
        for index in entries.indices {
            guard let landmarks = written[entries[index].id] else { continue }
            entries[index].markSaved(landmarks)
        }
    }

    /// What to say beside a yaw figure this detector cannot really support.
    ///
    /// Vision reports yaw in 45 degree steps -- on a six-face photograph it gave 0 for
    /// faces turned 13, 20 and 37 degrees. Now that the number reaches the panel, a bare
    /// "+0.00 degrees" would read as a frontal face rather than as a detector with
    /// nothing useful to say. `nil` when the figure stands on its own.
    public var yawCaveat: String? {
        detector == "vision" ? "vision rounds to 45\u{00B0} steps" : nil
    }
}
