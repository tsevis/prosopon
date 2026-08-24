import Foundation
import ProsoponMix
import ProsoponPipeline

/// Everything the toolbar and the banner need, and nothing else.
///
/// A flat value rather than a reference to the live app, for one reason: every string in
/// the chrome and every dimmed control is then a function of this, and can be checked by
/// building one of these and reading the answer. No window, no session, no folder on disk.
/// The SwiftUI files are left with layout and nothing to get wrong.
public struct ChromeState: Sendable, Equatable {

    // What has been imported
    public var sourceCount: Int
    public var imageCount: Int
    /// How many of the imported photographs the current run has already aligned.
    public var alreadyAlignedCount: Int
    public var unreadableSourceCount: Int

    // What the analysis produced
    public var runName: String?
    public var tileCount: Int
    public var acceptedCount: Int
    public var attentionCount: Int
    public var isAnalysing: Bool
    public var progress: BatchRunner.Progress?

    // What the reviewer has done since
    /// Changed and not yet written. Falls to zero on a save.
    public var editCount: Int
    /// Differs from what the detector found, saved or not — what Revert can undo.
    public var correctedCount: Int
    public var isSaving: Bool
    public var lastSaveSummary: String?
    /// A QA report that was found but could not be read. Worth saying out loud rather
    /// than letting the ordering it feeds quietly not work.
    public var qaReportProblem: String?

    // What the mix produced
    /// Aligned tiles a mix could use: the ones actually written, not the whole queue.
    public var mixTileCount: Int
    /// Composites written by the last mix, or planned by the last dry run.
    public var compositeCount: Int
    /// Tiles a composite could not take. A composite needs exactly four.
    public var mixLeftOverCount: Int
    public var isMixing: Bool
    public var mixProgress: MixRunner.Progress?
    public var lastMixSummary: String?

    public init(
        sourceCount: Int = 0,
        imageCount: Int = 0,
        alreadyAlignedCount: Int = 0,
        unreadableSourceCount: Int = 0,
        runName: String? = nil,
        tileCount: Int = 0,
        acceptedCount: Int = 0,
        attentionCount: Int = 0,
        isAnalysing: Bool = false,
        progress: BatchRunner.Progress? = nil,
        editCount: Int = 0,
        correctedCount: Int = 0,
        isSaving: Bool = false,
        lastSaveSummary: String? = nil,
        qaReportProblem: String? = nil,
        mixTileCount: Int = 0,
        compositeCount: Int = 0,
        mixLeftOverCount: Int = 0,
        isMixing: Bool = false,
        mixProgress: MixRunner.Progress? = nil,
        lastMixSummary: String? = nil
    ) {
        self.sourceCount = sourceCount
        self.imageCount = imageCount
        self.alreadyAlignedCount = alreadyAlignedCount
        self.unreadableSourceCount = unreadableSourceCount
        self.runName = runName
        self.tileCount = tileCount
        self.acceptedCount = acceptedCount
        self.attentionCount = attentionCount
        self.isAnalysing = isAnalysing
        self.progress = progress
        self.editCount = editCount
        self.correctedCount = correctedCount
        self.isSaving = isSaving
        self.lastSaveSummary = lastSaveSummary
        self.qaReportProblem = qaReportProblem
        self.mixTileCount = mixTileCount
        self.compositeCount = compositeCount
        self.mixLeftOverCount = mixLeftOverCount
        self.isMixing = isMixing
        self.mixProgress = mixProgress
        self.lastMixSummary = lastMixSummary
    }

    public var hasRun: Bool { runName != nil }
    public var rejectedCount: Int { max(0, tileCount - acceptedCount) }
    /// Imported photographs this run has not aligned yet.
    public var outstandingCount: Int { max(0, imageCount - alreadyAlignedCount) }

    /// How many quartered portraits the tiles on hand would make. Four to a canvas,
    /// every image used once, so the remainder simply does not make one.
    public var possibleCompositeCount: Int { mixTileCount / 4 }
}

// MARK: - The subject chip

/// What is loaded, and how far along it is.
///
/// The one line somebody glances at to know which batch they are in the middle of —
/// CrewListr's `S/Y ANEMOS · 6/6 cleared` is the same sentence about a different subject.
/// Prosopon's subject is the run, so the title names it and the detail says what stage it
/// has reached.
public enum SubjectChip {

    public static func title(_ state: ChromeState) -> String {
        if let runName = state.runName { return runName }
        if state.imageCount > 0 { return "Not analysed yet" }
        return "No portraits"
    }

    public static func detail(_ state: ChromeState) -> String? {
        if state.isAnalysing, let progress = state.progress {
            return "analysing \(progress.completed)/\(progress.total)"
        }
        if state.tileCount > 0 {
            var line = "\(state.acceptedCount)/\(state.tileCount) aligned"
            if state.editCount > 0 { line += " \u{00B7} \(state.editCount) edited" }
            return line
        }
        if state.imageCount > 0 {
            let sources = "\(state.sourceCount) source\(state.sourceCount == 1 ? "" : "s")"
            return "\(state.imageCount) portrait\(state.imageCount == 1 ? "" : "s") "
                + "from \(sources)"
        }
        return nil
    }

    public static let symbol = "square.grid.3x3.topleft.filled"
}
