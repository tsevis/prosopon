import ProsoponPipeline
import SwiftUI

/// The Analyze stage: what is about to be run, over what, and where it will land.
///
/// Deliberately thin. Every knob the command line has is not here — the defaults are the
/// ones the project settled on and a second place to change them is a second place for
/// them to disagree. What is here is the three decisions that change the result enough
/// that somebody should make them knowingly: which detector, how far a source may be
/// enlarged, and where the tiles go.
///
/// The enlargement limit earned its place the hard way. It was a constant at 2.0, and on
/// a corpus of ordinary studio portraits it declined seventeen of twenty with no way to
/// say otherwise — and no correction could help, because how far a face has to be
/// enlarged is fixed by the source resolution and the eye coordinates, not by where the
/// landmarks sit.
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
            magnificationChoice
            stretchChoice
            shearChoice
            outputChoice
        }
        .frame(maxWidth: 560, alignment: .leading)
    }

    private var stretchChoice: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Stretch a face at most")
                .font(Theme.Font.supportEmphasis)
                .foregroundStyle(Theme.ink)

            HStack(spacing: 10) {
                Slider(
                    value: Binding(
                        get: { state.maxStretch * 100 },
                        set: { state.maxStretch = $0.rounded() / 100 }
                    ),
                    in: 0...50, step: 1
                )
                .frame(maxWidth: 260)
                .tint(Theme.accent)

                Text(String(format: "%.0f%%", state.maxStretch * 100))
                    .font(Theme.Font.metric)
                    .foregroundStyle(Theme.ink)
                    .frame(width: 52, alignment: .leading)
            }

            Text("Both eyes are pinned exactly, so the only way to bring a mouth onto its "
                + "target is to stretch the face vertically about the eye line. This caps "
                + "that. Where the cap binds, the mouth is left short of the target \u{2014} "
                + "and on a quartered portrait the mouth sits exactly on a seam, so what is "
                + "left over is a step in the middle of the picture.")
                .font(Theme.Font.meta)
                .foregroundStyle(Theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Text("It costs less than it sounds. Measured on 204 portraits: at 5% the mouth "
                + "finished more than 20 px off on 68 tiles, at 12% on 4 \u{2014} while the "
                + "median face was stretched 4.9% either way, because the extra range is "
                + "only spent where the mouth was missing.")
                .font(Theme.Font.meta)
                .foregroundStyle(Theme.inkTertiary)
                .fixedSize(horizontal: false, vertical: true)

            Text("It also bounds every correction made in Fine Tune. Moving the mouth "
                + "marker asks for whatever stretch would bring that point onto the "
                + "target, and where this cap is lower than that, the marker moves and "
                + "the face does not \u{2014} which reads as the drag having done nothing. "
                + "Fine Tune reports both figures, as \u{201C}capped, wanted\u{201D}.")
                .font(Theme.Font.meta)
                .foregroundStyle(Theme.inkTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var shearChoice: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Shear a face at most")
                .font(Theme.Font.supportEmphasis)
                .foregroundStyle(Theme.ink)

            HStack(spacing: 10) {
                Slider(
                    value: Binding(
                        get: { state.maxShear * 100 },
                        set: { state.maxShear = $0.rounded() / 100 }
                    ),
                    in: 0...30, step: 1
                )
                .frame(maxWidth: 260)
                .tint(Theme.accent)

                Text(String(format: "%.0f%%", state.maxShear * 100))
                    .font(Theme.Font.metric)
                    .foregroundStyle(Theme.ink)
                    .frame(width: 52, alignment: .leading)
            }

            Text("The other half of placing a mouth. Stretch moves it up and down; shear "
                + "is the only thing that can slide it sideways with both eyes still "
                + "pinned, so it owns the horizontal exactly as stretch owns the "
                + "vertical. Set to nothing, the horizontal offset is left uncorrected "
                + "and the mouth lands wherever the face's own proportions put it.")
                .font(Theme.Font.meta)
                .foregroundStyle(Theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Text("One is not much use without the other. Measured on 204 portraits: at "
                + "25% stretch with shear left at 5%, the worst mouth still finished "
                + "32.5 px off target and every one of those pixels was horizontal. At "
                + "25% and 20% together, the worst was 0.0 px.")
                .font(Theme.Font.meta)
                .foregroundStyle(Theme.inkTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var magnificationChoice: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Enlarge a source at most")
                .font(Theme.Font.supportEmphasis)
                .foregroundStyle(Theme.ink)

            HStack(spacing: 10) {
                Slider(
                    value: Binding(
                        get: { state.maxMagnification },
                        set: { state.maxMagnification = ($0 * 10).rounded() / 10 }
                    ),
                    in: 1...8, step: 0.1
                )
                .frame(maxWidth: 260)
                .tint(Theme.accent)

                Text(String(format: "%.1f\u{00D7}", state.maxMagnification))
                    .font(Theme.Font.metric)
                    .foregroundStyle(Theme.ink)
                    .frame(width: 52, alignment: .leading)
            }

            Text("The canvas wants a face about a thousand pixels across. A photograph "
                + "shot smaller has to be enlarged to reach it, and past a point the tile "
                + "is visibly soft \u{2014} so this is a gate, and anything beyond it is "
                + "declined and not written. Raise it to keep tiles the default would "
                + "refuse; every one still reports the enlargement it needed.")
                .font(Theme.Font.meta)
                .foregroundStyle(Theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Text("A correction cannot get a tile past this. How far a face must be "
                + "enlarged follows from the source resolution and the fixed eye "
                + "coordinates, not from where the landmarks sit.")
                .font(Theme.Font.meta)
                .foregroundStyle(Theme.inkTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
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
