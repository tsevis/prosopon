import ProsoponCore
import SwiftUI

/// The queue of tiles, worst first.
///
/// Reviewing hundreds by hand is not the point — finding the handful the detector got
/// wrong is. So the ordering carries the work, and the list shows enough per row to
/// decide whether a tile needs opening at all.
struct TileListView: View {
    @Bindable var session: ReviewSession
    let thumbnails: ThumbnailCache

    var body: some View {
        VStack(spacing: 0) {
            Picker("Order", selection: $session.sortOrder) {
                ForEach(ReviewSortOrder.allCases, id: \.self) { order in
                    Text(order.label).tag(order)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .padding(8)

            List(session.entries, selection: $session.selection) { entry in
                TileRow(entry: entry, thumbnails: thumbnails)
                    .tag(entry.id)
            }
            .listStyle(.sidebar)
        }
    }
}

private struct TileRow: View {
    let entry: ReviewEntry
    let thumbnails: ThumbnailCache
    @State private var thumbnail: CGImage?
    /// The manifest named a file the decoder could not open. Distinguished from "there
    /// was never a file", because only one of the two is a fault.
    @State private var loadFailed = false

    var body: some View {
        HStack(spacing: 10) {
            thumbnailWell
                .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name).lineLimit(1)
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(needsAttention ? .orange : .secondary)
            }

            Spacer()
            if entry.isEdited {
                Image(systemName: "pencil.circle.fill").foregroundStyle(.yellow)
            }
        }
        .task(id: entry.outputURL) {
            loadFailed = false
            guard let url = entry.outputURL else { return }
            let loaded = await thumbnails.thumbnail(for: url)?.image
            thumbnail = loaded
            loadFailed = loaded == nil
        }
    }

    /// A rejected tile is never written, so there is nothing to load. Saying so is the
    /// whole point: an empty well reads as a failure, and a declined tile is not one.
    private var state: TileExportState {
        if case .exported(let url) = entry.exportState, loadFailed { return .missing(url) }
        return entry.exportState
    }

    @ViewBuilder
    private var thumbnailWell: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Theme.Radius.thumbnail).fill(Theme.canvasWell)
            if let thumbnail {
                Image(decorative: thumbnail, scale: 1)
                    .resizable().aspectRatio(contentMode: .fill)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.thumbnail))
            } else {
                let state = state
                Image(systemName: state.symbolName)
                    .font(.system(size: 15))
                    .foregroundStyle(state.isTrouble ? .orange : .secondary)
                RoundedRectangle(cornerRadius: Theme.Radius.thumbnail)
                    .strokeBorder(
                        style: StrokeStyle(lineWidth: 1, dash: [3, 2])
                    )
                    .foregroundStyle(.tertiary)
            }
        }
        .help(state.caption ?? entry.name)
    }

    private var needsAttention: Bool {
        entry.failure != nil
            || entry.quality?.isAccepted == false
            || entry.consensusMatched == false
            || (entry.consensusDisplacement ?? 0) > 2
            || loadFailed
    }

    private var summary: String {
        if let failure = entry.failure { return failure }
        if loadFailed, let caption = state.caption { return caption }
        if entry.consensusMatched == false { return "no match to the stack" }
        if let displacement = entry.consensusDisplacement {
            return String(format: "%.1f px from consensus", displacement)
        }
        guard let quality = entry.quality else { return "not solved" }
        if !quality.isAccepted {
            return quality.rejections.map(TileExportState.phrase).joined(separator: ", ")
        }
        return String(format: "score %.2f", quality.score)
    }
}
