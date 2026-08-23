import Foundation

/// One line under the toolbar saying, in plain language, where the work stands.
///
/// Plain language means the sentence somebody would say out loud — "13 of 16 aligned.
/// Three could not be used." — rather than a count of enum cases. It is the only place in
/// the window that describes the whole state rather than one tile, which is why it sits
/// in the chrome and not in a panel.
public struct StatusBanner: Sendable, Equatable {

    /// Nothing is in the way, or something is. Two states and no more: a third would need
    /// a colour to distinguish it and the palette is one hue.
    public enum Kind: Sendable { case notice, caution }

    public let kind: Kind
    public let symbol: String
    public let text: String
    /// Anything further worth knowing, shown as a count with the lines behind it.
    public let extra: [String]

    public init(kind: Kind, symbol: String, text: String, extra: [String] = []) {
        self.kind = kind
        self.symbol = symbol
        self.text = text
        self.extra = extra
    }

    private static func notice(_ text: String, extra: [String] = []) -> StatusBanner {
        StatusBanner(kind: .notice, symbol: "checkmark.seal.fill", text: text, extra: extra)
    }

    private static func caution(_ text: String, extra: [String] = []) -> StatusBanner {
        StatusBanner(
            kind: .caution, symbol: "exclamationmark.triangle.fill", text: text, extra: extra
        )
    }

    /// What to say, given where the work stands.
    ///
    /// Ordered by urgency rather than by stage, because the banner has one line and a
    /// source that cannot be read matters more than a tally that is going fine. A problem
    /// anywhere is worth interrupting the current stage's own news for.
    public static func message(for stage: Stage, state: ChromeState) -> StatusBanner {
        if state.unreadableSourceCount > 0 {
            let n = state.unreadableSourceCount
            return caution(
                "\(n) source\(n == 1 ? "" : "s") could not be read. "
                    + "A folder that has moved or is on a volume that is not mounted "
                    + "reports no images rather than an error."
            )
        }
        if let problem = state.qaReportProblem {
            return caution("The QA report could not be read, so the queue is not ordered "
                + "by distance from the stack.", extra: [problem])
        }
        if state.isAnalysing, let progress = state.progress {
            return notice("Analysing \(progress.completed) of \(progress.total) photographs.")
        }

        switch stage {
        case .importPortraits: return importMessage(state)
        case .analyze: return analyzeMessage(state)
        case .fineTune: return fineTuneMessage(state)
        }
    }

    private static func importMessage(_ state: ChromeState) -> StatusBanner {
        if state.sourceCount == 0 {
            return notice("Add a folder of portraits to begin. "
                + "Drag one onto the window, or use Add.")
        }
        if state.imageCount == 0 {
            return caution("Nothing here is a photograph Prosopon can open. "
                + "Turn on Look Inside Folders if the images are in subfolders.")
        }

        let images = "\(state.imageCount) portrait\(state.imageCount == 1 ? "" : "s")"
        if state.alreadyAlignedCount == 0 {
            return notice("\(images) found, none of them aligned yet.")
        }
        if state.outstandingCount == 0 {
            return notice("\(images) found, and this run has already aligned all of them.")
        }
        return notice("\(images) found. \(state.alreadyAlignedCount) already aligned, "
            + "\(state.outstandingCount) still to do.")
    }

    private static func analyzeMessage(_ state: ChromeState) -> StatusBanner {
        if state.tileCount == 0 {
            return state.imageCount == 0
                ? caution("There is nothing to analyse yet. Import some portraits first.")
                : notice("Ready to analyse \(state.outstandingCount) "
                    + "portrait\(state.outstandingCount == 1 ? "" : "s").")
        }
        if state.rejectedCount == 0 {
            return notice("All \(state.tileCount) tiles cleared their gates.")
        }
        // A declined tile is the gates working, not a failure -- but it is a number
        // somebody should see before stacking, so it does not pass without comment.
        return caution(
            "\(state.acceptedCount) of \(state.tileCount) aligned. "
                + "\(state.rejectedCount) could not be used and were not written."
        )
    }

    private static func fineTuneMessage(_ state: ChromeState) -> StatusBanner {
        if state.tileCount == 0 {
            return caution("No run is open. Analyse some portraits, or open a folder "
                + "an earlier run wrote.")
        }
        if state.isSaving {
            return notice("Saving corrections\u{2026}")
        }
        if state.editCount > 0 {
            let n = state.editCount
            return caution("\(n) correction\(n == 1 ? "" : "s") not yet saved. "
                + "Saving re-renders only the tiles that changed.")
        }
        if state.attentionCount > 0 {
            let n = state.attentionCount
            return caution("\(n) tile\(n == 1 ? "" : "s") need\(n == 1 ? "s" : "") "
                + "attention. The queue puts the worst first.")
        }
        if let summary = state.lastSaveSummary {
            return notice("Saved \u{2014} \(summary).")
        }
        return notice("Every tile cleared its gates. Nothing here needs correcting.")
    }
}
