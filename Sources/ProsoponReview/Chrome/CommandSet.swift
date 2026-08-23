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
        [
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
                isEnabled: state.editCount > 0 && !state.isSaving,
                help: "Put the selected tile's landmarks back where the detector had them"
            ),
            Command(
                action: .saveCorrections,
                title: saveTitle(state),
                symbol: "square.and.arrow.down",
                weight: .primary,
                isEnabled: state.editCount > 0 && !state.isSaving,
                help: "Re-render only the tiles that changed, and update the manifest in place"
            ),
        ]
    }

    private static func saveTitle(_ state: ChromeState) -> String {
        if state.isSaving { return "Saving\u{2026}" }
        guard state.editCount > 0 else { return "Save" }
        return "Save \(state.editCount) Correction\(state.editCount == 1 ? "" : "s")"
    }
}
