import Foundation

/// Something the toolbar can do. The view knows how to draw one; it does not decide
/// which ones exist or whether they are available.
public struct Command: Sendable, Equatable, Identifiable {

    /// How loudly it is drawn. Exactly one `primary` per stage — an accent used twice is
    /// an accent used nowhere.
    public enum Weight: Sendable { case primary, secondary, quiet }

    public let action: ChromeAction
    public let title: String
    public let symbol: String
    public let weight: Weight
    public let isEnabled: Bool
    public let help: String

    public var id: ChromeAction { action }
}

public enum ChromeAction: String, Sendable, CaseIterable {
    case addSources
    case removeAllSources
    case chooseOutputFolder
    case analyse
    case cancelAnalysis
    case openRun
    case revertTile
    case saveCorrections
    case goToAnalyze
    case goToFineTune
    case goToMix
    case chooseMixFolder
    case mix
    case cancelMix
}

/// Which actions belong to which stage, in priority order, and when each is available.
///
/// Unavailable actions are **returned and dimmed, never omitted**. A control that
/// disappears takes with it the knowledge that it exists, and then the question is not
/// "why is Save grey" but "where has Save gone".
public enum CommandSet {

    public static func commands(for stage: Stage, state: ChromeState) -> [Command] {
        switch stage {
        case .importPortraits: importCommands(state)
        case .analyze: analyzeCommands(state)
        case .fineTune: fineTuneCommands(state)
        case .mix: mixCommands(state)
        }
    }

    // MARK: Import

    private static func importCommands(_ state: ChromeState) -> [Command] {
        [
            Command(
                action: .removeAllSources,
                title: "Remove All",
                symbol: "trash",
                weight: .quiet,
                isEnabled: state.sourceCount > 0 && !state.isAnalysing,
                help: "Forget every folder and photograph added here. Nothing is deleted."
            ),
            Command(
                action: .addSources,
                title: "Add\u{2026}",
                symbol: "plus",
                weight: .secondary,
                isEnabled: !state.isAnalysing,
                help: "Choose folders and photographs. Both at once, and as many as you like."
            ),
            Command(
                action: .analyse,
                title: analyseTitle(state),
                symbol: "viewfinder",
                weight: .primary,
                isEnabled: state.outstandingCount > 0 && !state.isAnalysing,
                help: analyseHelp(state)
            ),
        ]
    }

    private static func analyseTitle(_ state: ChromeState) -> String {
        guard state.imageCount > 0 else { return "Analyse" }
        let outstanding = state.outstandingCount
        guard outstanding > 0 else { return "All Analysed" }
        return "Analyse \(outstanding) Portrait\(outstanding == 1 ? "" : "s")"
    }

    private static func analyseHelp(_ state: ChromeState) -> String {
        if state.imageCount == 0 { return "Add some portraits first" }
        if state.outstandingCount == 0 {
            return "Every imported portrait is already in this run"
        }
        return "Find the face in each photograph, solve its alignment, and write the tiles"
    }

    // MARK: Analyze

    private static func analyzeCommands(_ state: ChromeState) -> [Command] {
        [
            Command(
                action: .cancelAnalysis,
                title: "Stop",
                symbol: "stop.circle",
                weight: .quiet,
                isEnabled: state.isAnalysing,
                help: "Stop after the photographs already in flight. What was written stays."
            ),
            Command(
                action: .chooseOutputFolder,
                title: "Output Folder\u{2026}",
                symbol: "folder",
                weight: .quiet,
                isEnabled: !state.isAnalysing,
                help: "Where the aligned tiles and the manifest are written"
            ),
            Command(
                action: .analyse,
                title: state.tileCount > 0 ? "Analyse Again" : analyseTitle(state),
                symbol: "arrow.clockwise",
                weight: state.tileCount > 0 ? .secondary : .primary,
                isEnabled: state.outstandingCount > 0 && !state.isAnalysing,
                help: analyseHelp(state)
            ),
            Command(
                action: .goToFineTune,
                title: fineTuneTitle(state),
                symbol: "slider.horizontal.below.rectangle",
                weight: .primary,
                isEnabled: state.tileCount > 0 && !state.isAnalysing,
                help: "Look at the tiles, worst first, and correct what the detector missed"
            ),
        ]
        // Before there is anything to fine tune, Analyse is the one filled control; after,
        // it steps back and Fine Tune takes the fill. Never two.
        .filter { !($0.action == .goToFineTune && state.tileCount == 0) }
    }

    private static func fineTuneTitle(_ state: ChromeState) -> String {
        guard state.attentionCount > 0 else { return "Fine Tune" }
        return "Fine Tune \(state.attentionCount)"
    }

    // MARK: Fine Tune

    private static func fineTuneCommands(_ state: ChromeState) -> [Command] {
        // Unsaved work is the one thing that must not be walked away from, so it takes the
        // fill while there is any. With nothing outstanding the fill moves to the step
        // that comes next, which is what every other stage does too.
        let hasEdits = state.editCount > 0
        return [
            Command(
                action: .openRun,
                title: "Open Run\u{2026}",
                symbol: "folder",
                weight: .quiet,
                isEnabled: !state.isSaving,
                help: "Open a folder written by an earlier run"
            ),
            Command(
                action: .revertTile,
                title: "Revert",
                symbol: "arrow.uturn.backward",
                weight: .quiet,
                // Corrections, not unsaved ones: a correction that has been written is
                // still a correction, and putting it back is exactly what somebody who
                // has just looked at the result wants to do.
                isEnabled: state.correctedCount > 0 && !state.isSaving,
                help: "Put the selected tile's landmarks back where the detector had them"
            ),
            Command(
                action: .saveCorrections,
                title: saveTitle(state),
                symbol: "square.and.arrow.down",
                weight: hasEdits ? .primary : .secondary,
                isEnabled: hasEdits && !state.isSaving,
                help: "Re-render only the tiles that changed, and update the manifest in place"
            ),
            Command(
                action: .goToMix,
                title: "Mix",
                symbol: "square.grid.2x2",
                weight: hasEdits ? .secondary : .primary,
                isEnabled: state.tileCount > 0 && !state.isSaving && !state.isMixing,
                help: "Compose these tiles into quartered portraits, four faces to a canvas"
            ),
        ]
    }

    // MARK: Mix

    private static func mixCommands(_ state: ChromeState) -> [Command] {
        [
            Command(
                action: .cancelMix,
                title: "Stop",
                symbol: "stop.circle",
                weight: .quiet,
                isEnabled: state.isMixing,
                help: "Stop after the composites already in flight. What was written stays."
            ),
            Command(
                action: .chooseMixFolder,
                title: "Output Folder\u{2026}",
                symbol: "folder",
                weight: .quiet,
                isEnabled: !state.isMixing,
                help: "Where the composites, their previews and the mix manifest are written"
            ),
            Command(
                action: .mix,
                title: mixTitle(state),
                symbol: "square.grid.2x2",
                weight: .primary,
                isEnabled: state.possibleCompositeCount > 0 && !state.isMixing,
                help: mixHelp(state)
            ),
        ]
    }

    private static func mixTitle(_ state: ChromeState) -> String {
        if state.isMixing { return "Mixing\u{2026}" }
        let possible = state.possibleCompositeCount
        guard possible > 0 else { return "Mix" }
        if state.compositeCount > 0 { return "Mix Again" }
        return "Mix \(possible) Composite\(possible == 1 ? "" : "s")"
    }

    private static func mixHelp(_ state: ChromeState) -> String {
        if state.mixTileCount == 0 {
            return "Align some portraits first \u{2014} a mix is made from written tiles"
        }
        if state.possibleCompositeCount == 0 {
            return "\(state.mixTileCount) tile\(state.mixTileCount == 1 ? "" : "s") is not enough; "
                + "a composite needs exactly four"
        }
        return "Four faces to a canvas, each image used once. The mouth seam is matched "
            + "first, then the cheeks."
    }

    private static func saveTitle(_ state: ChromeState) -> String {
        if state.isSaving { return "Saving\u{2026}" }
        guard state.editCount > 0 else { return "Save" }
        return "Save \(state.editCount) Correction\(state.editCount == 1 ? "" : "s")"
    }
}
