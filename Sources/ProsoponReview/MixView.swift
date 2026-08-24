import ProsoponMix
import SwiftUI

/// The Mix stage: what is about to be composed, and what came out.
///
/// Deliberately thin, like the other stage views — every string in the toolbar and the
/// banner is decided in `CommandSet` and `StatusBanner`, and what is left here is
/// arrangement. The one thing this stage has that the others do not is the work itself on
/// screen: a composite is a picture, and whether a mouth joins is a question only looking
/// can answer.
struct MixView: View {
    let state: AppState
    let thumbnails: ThumbnailCache
    let onChooseOutput: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if state.isMixing {
                    running
                } else if state.mixTileCount == 0 {
                    EmptyStateView(
                        symbol: "square.grid.2x2",
                        title: "Nothing to mix",
                        message: "A composite is cut from four aligned tiles. Analyse some "
                            + "portraits first, or open a run that already has tiles in it."
                    )
                } else {
                    settings
                }

                if let manifest = state.mixManifest, let directory = state.mixDirectory {
                    results(manifest, directory: directory)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Theme.Space.workspace)
        }
    }

    // MARK: While it runs

    private var running: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(state.mixProgress?.phase == .measuring ? "Measuring the seams" : "Composing")
                .font(Theme.Font.panelTitle)
                .foregroundStyle(Theme.ink)
            if let progress = state.mixProgress {
                ProgressView(value: progress.fraction) {
                    Text("\(progress.completed) of \(progress.total)")
                        .font(Theme.Font.support)
                        .foregroundStyle(Theme.inkSecondary)
                }
                .progressViewStyle(.linear)
                .tint(Theme.accent)
                .frame(maxWidth: 460)
            }
            Text("Every tile is measured along the four seams before anything is composed, "
                + "because the assignment cannot be made until all of them are known.")
                .font(Theme.Font.meta)
                .foregroundStyle(Theme.inkTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Before it runs

    private var settings: some View {
        VStack(alignment: .leading, spacing: 18) {
            howItWorks
            seedChoice
            outputChoice
        }
        .frame(maxWidth: 620, alignment: .leading)
    }

    private var howItWorks: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Four faces to a canvas")
                .font(Theme.Font.supportEmphasis)
                .foregroundStyle(Theme.ink)
            Text("The seams fall at the middle of the canvas, which puts an eye well inside "
                + "each top quadrant and the mouth exactly on the vertical seam \u{2014} so "
                + "the two bottom quadrants carry half a mouth each, from two different "
                + "people. That is the hardest join, and it is the one matched first.")
                .font(Theme.Font.meta)
                .foregroundStyle(Theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var seedChoice: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Seed")
                .font(Theme.Font.supportEmphasis)
                .foregroundStyle(Theme.ink)
            HStack(spacing: 8) {
                Stepper(
                    value: Binding(
                        get: { Int(state.mixSeed) },
                        set: { state.mixSeed = UInt64(max(0, $0)) }
                    ),
                    in: 0...9999
                ) {
                    Text("\(state.mixSeed)")
                        .font(Theme.Font.support)
                        .monospacedDigit()
                        .foregroundStyle(Theme.ink)
                }
                .frame(maxWidth: 160, alignment: .leading)
            }
            Text("The matching is decided by the pixels either side of each seam, but the "
                + "order tiles are offered in is not. Another seed gives another batch from "
                + "the same corpus, and the same seed gives the same one back.")
                .font(Theme.Font.meta)
                .foregroundStyle(Theme.inkTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var outputChoice: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Composites go to")
                .font(Theme.Font.supportEmphasis)
                .foregroundStyle(Theme.ink)
            HStack(spacing: 8) {
                Image(systemName: "folder").foregroundStyle(Theme.accentText)
                Text(state.mixOutputDirectory?.path ?? "a mixed folder inside the run")
                    .font(Theme.Font.meta)
                    .foregroundStyle(
                        state.mixOutputDirectory == nil ? Theme.inkTertiary : Theme.inkSecondary
                    )
                    .lineLimit(1)
                    .truncationMode(.middle)
                Button("Change\u{2026}", action: onChooseOutput)
                    .buttonStyle(.prosoponQuiet)
            }
            Text("Each composite is one layered document of about 30 MB, with the four "
                + "quadrants as positioned layers and the three landmark markers hidden on "
                + "top. A flattened preview is written beside it.")
                .font(Theme.Font.meta)
                .foregroundStyle(Theme.inkTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: What came out

    private func results(_ manifest: MixManifest, directory: URL) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider().overlay(Theme.hairline)

            HStack(spacing: 10) {
                Text("\(manifest.composites.count) composite\(manifest.composites.count == 1 ? "" : "s")")
                    .font(Theme.Font.panelTitle)
                    .foregroundStyle(Theme.ink)
                StatusChip(symbol: "number", text: "seed \(manifest.seed)")
                StatusChip(symbol: "person.crop.square", text: manifest.frontalityBasis.rawValue)
            }

            Text(manifest.frontalityNote)
                .font(Theme.Font.meta)
                .foregroundStyle(Theme.inkTertiary)
                .fixedSize(horizontal: false, vertical: true)

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 220, maximum: 300), spacing: 14)],
                spacing: 14
            ) {
                ForEach(manifest.composites, id: \.index) { composite in
                    CompositeCard(
                        composite: composite,
                        previewURL: manifest.previewURL(for: composite, in: directory),
                        thumbnails: thumbnails
                    )
                }
            }

            if !manifest.unused.isEmpty {
                unused(manifest.unused)
            }
        }
    }

    private func unused(_ tiles: [UnusedTile]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(tiles.count) tile\(tiles.count == 1 ? "" : "s") left over")
                .font(Theme.Font.supportEmphasis)
                .foregroundStyle(Theme.cautionInk)
            ForEach(tiles, id: \.tilePath) { tile in
                Text("\(tile.name) \u{2014} \(tile.reason)")
                    .font(Theme.Font.meta)
                    .foregroundStyle(Theme.inkSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }
}

/// One composite: what it looks like, and how well its seams came out.
private struct CompositeCard: View {
    let composite: CompositeRecord
    let previewURL: URL?
    let thumbnails: ThumbnailCache

    @State private var image: CGImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            preview
            Text(composite.documentPath ?? String(format: "mix-%04d (planned)", composite.index + 1))
                .font(Theme.Font.supportEmphasis)
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
            if let mouth = composite.mouthSeam {
                Text(String(format: "mouth seam %.1f", mouth))
                    .font(Theme.Font.meta)
                    .monospacedDigit()
                    .foregroundStyle(mouth > 15 ? Theme.cautionInk : Theme.inkSecondary)
            }
            ForEach(composite.quadrants, id: \.quadrant) { quadrant in
                Text("\(quadrant.quadrant.label) \u{00B7} \(quadrant.name)")
                    .font(Theme.Font.meta)
                    .foregroundStyle(Theme.inkTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(10)
        .background(Theme.panel)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous))
        .help(helpText)
        .task(id: previewURL) { await load() }
    }

    @ViewBuilder
    private var preview: some View {
        // The canvas behind a photograph deliberately does not follow the appearance: a
        // composite is judged against its own halves, and a light surround changes what
        // the eye makes of a join.
        ZStack {
            Rectangle().fill(Theme.canvasWell)
            if let image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .aspectRatio(1, contentMode: .fit)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
    }

    private var helpText: String {
        composite.seams
            .sorted { $0.key < $1.key }
            .map { String(format: "%@ %.1f", $0.key, $0.value) }
            .joined(separator: "  \u{00B7}  ")
    }

    private func load() async {
        guard let previewURL else { return }
        image = await thumbnails.thumbnail(for: previewURL)?.image
    }
}
