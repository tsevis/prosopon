import ProsoponPipeline
import SwiftUI

/// The Analyze stage: what is about to be run, over what, and where it will land.
///
/// Deliberately thin. Every knob the command line has is not here — the defaults are the
/// ones the project settled on and a second place to change them is a second place for
/// them to disagree. What is here is the two decisions that change the result enough that
/// somebody should make them knowingly: which detector, and where the tiles go.
struct AnalyzeView: View {
    let state: AppState
    let onChooseOutput: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if state.isAnalysing {
                running
            } else if state.chrome.imageCount == 0 {
                EmptyStateView(
                    symbol: "viewfinder",
                    title: "Nothing to analyse",
                    message: "Import some portraits first. Analyze finds the face in each "
                        + "one, solves its alignment onto the canvas, and writes the tile."
                )
            } else {
                settings
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Space.workspace)
    }

    // MARK: While it runs

    private var running: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Analysing")
                .font(Theme.Font.panelTitle)
                .foregroundStyle(Theme.ink)
            if let progress = state.progress {
                ProgressView(value: progress.fraction) {
                    Text("\(progress.completed) of \(progress.total) photographs")
                        .font(Theme.Font.support)
                        .foregroundStyle(Theme.inkSecondary)
                }
                .progressViewStyle(.linear)
                .tint(Theme.accent)
                .frame(maxWidth: 460)
            }
            Text("Stopping leaves everything already written in place \u{2014} it is not "
                + "undone, and the run can be finished later.")
                .font(Theme.Font.meta)
                .foregroundStyle(Theme.inkTertiary)
        }
    }

    // MARK: Before it runs

    private var settings: some View {
        VStack(alignment: .leading, spacing: 18) {
            detectorChoice
            outputChoice
        }
        .frame(maxWidth: 560, alignment: .leading)
    }

    private var detectorChoice: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Landmarks from")
                .font(Theme.Font.supportEmphasis)
                .foregroundStyle(Theme.ink)

            Picker("", selection: Binding(
                get: { state.detector }, set: { state.detector = $0 }
            )) {
                ForEach(DetectorChoice.allCases) { choice in
                    Text(choice.label).tag(choice)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 260, alignment: .leading)

            Text(state.detector.detail)
                .font(Theme.Font.meta)
                .foregroundStyle(Theme.inkSecondary)

            if !state.detector.reportsUsableYaw {
                // The one respect in which the tiers are measurably different, and it is
                // invisible until somebody tries to sort by pose and finds every face
                // reporting zero.
                Text("Vision reports head yaw only in 45\u{00B0} steps \u{2014} on a "
                    + "six-face photograph it gave 0\u{00B0} for faces turned 13, 20 and "
                    + "37\u{00B0}. If pose matters, InsightFace tracks it to half a degree.")
                    .font(Theme.Font.meta)
                    .foregroundStyle(Theme.inkTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var outputChoice: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Aligned tiles go to")
                .font(Theme.Font.supportEmphasis)
                .foregroundStyle(Theme.ink)

            HStack(spacing: 8) {
                Image(systemName: "folder")
                    .foregroundStyle(Theme.accentText)
                Text(state.outputDirectory?.path ?? "chosen for you when the run starts")
                    .font(Theme.Font.meta)
                    .foregroundStyle(
                        state.outputDirectory == nil ? Theme.inkTertiary : Theme.inkSecondary
                    )
                    .lineLimit(1)
                    .truncationMode(.middle)
                Button("Change\u{2026}", action: onChooseOutput)
                    .buttonStyle(.prosoponQuiet)
            }

            Text("The manifest written here records the landmarks and the transform for "
                + "every tile, which is what lets a correction re-render one photograph "
                + "without detecting anything again.")
                .font(Theme.Font.meta)
                .foregroundStyle(Theme.inkTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
