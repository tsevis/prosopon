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

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 4).fill(Color(white: 0.2))
                if let thumbnail {
                    Image(decorative: thumbnail, scale: 1)
                        .resizable().aspectRatio(contentMode: .fill)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
            }
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
            guard let url = entry.outputURL else { return }
            thumbnail = await thumbnails.thumbnail(for: url)?.image
        }
    }

    private var needsAttention: Bool {
        entry.failure != nil
            || entry.quality?.isAccepted == false
            || entry.consensusMatched == false
            || (entry.consensusDisplacement ?? 0) > 2
    }

    private var summary: String {
        if let failure = entry.failure { return failure }
        if entry.consensusMatched == false { return "no match to the stack" }
        if let displacement = entry.consensusDisplacement {
            return String(format: "%.1f px from consensus", displacement)
        }
        guard let quality = entry.quality else { return "not solved" }
        if !quality.isAccepted { return quality.rejections.map(\.rawValue).joined(separator: ", ") }
        return String(format: "score %.2f", quality.score)
    }
}
