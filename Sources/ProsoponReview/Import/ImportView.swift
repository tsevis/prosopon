import ProsoponPipeline
import QuickLook
import SwiftUI

/// The Import stage: what has been added on the left, what was found in it on the right.
///
/// Nothing here starts work. The whole purpose is to be able to say, before committing to
/// a run over several thousand photographs, exactly what is about to happen to how many
/// of them — which is why the counts are the loudest thing on the screen.
struct ImportView: View {
    let state: AppState
    /// The photographs the current run has already aligned, so the grid can say which
    /// ones a run would leave alone.
    let alignedPaths: Set<String>
    let thumbnails: ThumbnailCache
    let onAdd: () -> Void

    @State private var quickLookURL: URL?
    @State private var selected: URL?

    private var library: SourceLibrary { state.sources }

    var body: some View {
        HSplitView {
            sourceList
                .frame(minWidth: 240, idealWidth: 300, maxWidth: 420)
            grid
                .frame(minWidth: 360)
        }
        .padding(.horizontal, Theme.Space.workspace)
        .padding(.vertical, 12)
        .quickLookPreview($quickLookURL, in: library.scan.imageURLs)
    }

    // MARK: Sources

    private var sourceList: some View {
        VStack(alignment: .leading, spacing: 0) {
            PanelHeading("Sources", detail: sourcesDetail) {
                if !library.missing.isEmpty {
                    // One button for the whole panel, because the rows below it are not
                    // twenty separate misfortunes: a corpus goes missing all at once,
                    // when a volume is unplugged or a build stops recognising its own
                    // bookmarks, and clearing that one event should cost one click.
                    Button("Forget All") { library.forgetAllMissing() }
                        .buttonStyle(.plain)
                        .font(Theme.Font.meta)
                        .foregroundStyle(Theme.cautionInk)
                        .help("Remove all \(library.missing.count) sources that could not be "
                            + "opened. The photographs themselves are not touched.")
                }
            }

            if library.sources.isEmpty && library.missing.isEmpty {
                EmptyStateView(
                    symbol: "folder.badge.plus",
                    title: "Nothing added yet",
                    message: "Drag folders or photographs onto this window, or use Add. "
                        + "Folders and single files can be mixed freely."
                ) {
                    Button("Add\u{2026}", action: onAdd).buttonStyle(.prosoponSecondary)
                }
            } else {
                List {
                    ForEach(library.sources) { source in
                        SourceRow(
                            source: source,
                            count: library.count(of: source),
                            unreadable: library.scan.unreadable[source.url],
                            excluded: library.scan.excluded[source.url],
                            onToggleRecursive: { library.setRecursive($0, for: source) },
                            onReveal: { library.reveal(source) },
                            onRemove: { library.remove(source) }
                        )
                    }
                    ForEach(library.missing) { missing in
                        MissingSourceRow(missing: missing) { library.forget(missing) }
                    }
                }
                .listStyle(.inset)
            }
        }
        .background(Theme.panel)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous)
                .strokeBorder(Theme.hairline, lineWidth: 1)
        )
    }

    /// Says what is missing as well as what is there. "none" over a list of twenty rows
    /// is not a heading anybody can act on.
    private var sourcesDetail: String {
        var parts: [String] = []
        if library.sources.count > 0 {
            parts.append("\(library.sources.count) \u{00B7} \(library.scan.imageCount) images")
        }
        if !library.missing.isEmpty { parts.append("\(library.missing.count) missing") }
        return parts.isEmpty ? "none" : parts.joined(separator: " \u{00B7} ")
    }

    // MARK: What was found

    private var grid: some View {
        VStack(alignment: .leading, spacing: 0) {
            PanelHeading("Portraits found", detail: gridDetail)

            if library.scan.isEmpty {
                EmptyStateView(
                    symbol: "photo.on.rectangle.angled",
                    title: "No photographs yet",
                    message: "Prosopon reads the usual formats \u{2014} JPEG, PNG, TIFF, HEIC "
                        + "and camera raw. Press space on any thumbnail to look at it full size."
                )
            } else {
                ScrollView {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 96), spacing: 10)],
                        spacing: 10
                    ) {
                        ForEach(library.scan.imageURLs, id: \.self) { url in
                            Thumbnail(
                                url: url,
                                isAligned: alignedPaths.contains(url.standardizedFileURL.path),
                                isSelected: selected == url,
                                thumbnails: thumbnails
                            )
                            .onTapGesture { selected = url }
                            .onTapGesture(count: 2) { quickLookURL = url }
                        }
                    }
                    .padding(12)
                }
                // Space previews the selection, the way it does in Finder. The panel
                // takes the whole list, so its own arrow keys then walk the corpus.
                .focusable()
                .focusEffectDisabled()
                .onKeyPress(.space) {
                    guard let url = selected ?? library.scan.imageURLs.first else {
                        return .ignored
                    }
                    quickLookURL = url
                    return .handled
                }
                .onKeyPress(.leftArrow) { move(by: -1) }
                .onKeyPress(.rightArrow) { move(by: 1) }
            }
        }
        .background(Theme.panel)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous)
                .strokeBorder(Theme.hairline, lineWidth: 1)
        )
    }

    /// Walks the grid so a corpus can be looked through from the keyboard without
    /// opening Quick Look at all.
    private func move(by delta: Int) -> KeyPress.Result {
        let urls = library.scan.imageURLs
        guard !urls.isEmpty else { return .ignored }
        let current = selected.flatMap { urls.firstIndex(of: $0) } ?? 0
        selected = urls[min(max(current + delta, 0), urls.count - 1)]
        return .handled
    }

    private var gridDetail: String {
        let aligned = library.alreadyAligned(inRunWith: alignedPaths)
        guard aligned > 0 else { return "\(library.scan.imageCount)" }
        return "\(library.scan.imageCount) \u{00B7} \(aligned) already aligned"
    }
}

// MARK: - Rows

private struct SourceRow: View {
    let source: ImageSource
    let count: Int
    let unreadable: String?
    /// Left out on purpose, with the reason. Not a failure, so it does not read as one —
    /// but never silent either, since a folder showing no images and saying nothing is
    /// the thing this is here to prevent.
    let excluded: String?
    let onToggleRecursive: (Bool) -> Void
    let onReveal: () -> Void
    let onRemove: () -> Void

    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: source.isDirectory ? "folder.fill" : "photo")
                .foregroundStyle(Theme.accentText)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(source.url.lastPathComponent)
                    .font(Theme.Font.body)
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(detail)
                    .font(Theme.Font.meta)
                    .foregroundStyle(unreadable == nil ? Theme.inkSecondary : Theme.cautionInk)
                    .help(excluded ?? "")
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            if source.isDirectory {
                // Visible rather than buried in a preference, because these corpora nest
                // and the count on the right changes the moment it is flipped.
                Toggle("", isOn: Binding(
                    get: { source.isRecursive },
                    set: { onToggleRecursive($0) }
                ))
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
                .help("Look inside subfolders")
            }

            Button(action: onRemove) { Image(systemName: "xmark") }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.inkTertiary)
                .opacity(hovering ? 1 : 0)
                .help("Remove this source. Nothing on disk is touched.")
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .contextMenu {
            Button("Reveal in Finder", action: onReveal)
            Button("Remove", role: .destructive, action: onRemove)
        }
    }

    private var detail: String {
        if let excluded { return excluded }
        if unreadable != nil { return "could not be read" }
        guard source.isDirectory else { return "one photograph" }
        return "\(count) image\(count == 1 ? "" : "s")"
            + (source.isRecursive ? ", including subfolders" : ", this folder only")
    }
}

/// A folder that was remembered but is no longer where it was.
///
/// Shown rather than dropped: silently forgetting it is how somebody loses a corpus they
/// added months ago and never notices the count went down.
private struct MissingSourceRow: View {
    let missing: MissingSource
    let onForget: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "questionmark.folder")
                .foregroundStyle(Theme.cautionInk)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(missing.name)
                    .font(Theme.Font.body)
                    .foregroundStyle(Theme.inkSecondary)
                    .lineLimit(1)
                Text("missing \u{2014} moved, renamed, or on a volume that is not mounted")
                    .font(Theme.Font.meta)
                    .foregroundStyle(Theme.cautionInk)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            Button("Forget", action: onForget)
                .buttonStyle(.plain)
                .font(Theme.Font.meta)
                .foregroundStyle(Theme.inkTertiary)
        }
        .padding(.vertical, 3)
        .help(missing.path + "\n\n" + missing.reason)
    }
}

private struct Thumbnail: View {
    let url: URL
    let isAligned: Bool
    let isSelected: Bool
    let thumbnails: ThumbnailCache

    @State private var image: CGImage?

    var body: some View {
        VStack(spacing: 4) {
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: Theme.Radius.thumbnail)
                    .fill(Theme.controlTrack)
                    .aspectRatio(1, contentMode: .fit)
                if let image {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.thumbnail))
                }
                if isAligned {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.accent)
                        .background(Circle().fill(.white))
                        .padding(4)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.thumbnail)
                    .strokeBorder(isSelected ? Theme.accent : .clear, lineWidth: 2)
            )
            Text(url.deletingPathExtension().lastPathComponent)
                .font(Theme.Font.meta)
                .foregroundStyle(Theme.inkSecondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .help(isAligned
            ? "\(url.lastPathComponent) \u{2014} already aligned in this run. Space to look at it."
            : "\(url.lastPathComponent) \u{2014} space to look at it.")
        .task(id: url) { image = await thumbnails.thumbnail(for: url)?.image }
    }
}

/// A panel's own heading. The only thing a panel gets to carry besides its content —
/// every action lives in the command bar.
struct PanelHeading<Trailing: View>: View {
    let title: String
    let detail: String?
    /// Sits at the right of the heading, for the one action that is about the whole
    /// panel rather than about any row in it.
    @ViewBuilder let trailing: Trailing

    init(_ title: String, detail: String? = nil, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.detail = detail
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .font(Theme.Font.supportEmphasis)
                .foregroundStyle(Theme.ink)
            if let detail {
                Text(detail)
                    .font(Theme.Font.meta.monospacedDigit())
                    .foregroundStyle(Theme.inkTertiary)
            }
            Spacer(minLength: 0)
            trailing
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }
}

extension PanelHeading where Trailing == EmptyView {
    init(_ title: String, detail: String? = nil) {
        self.init(title, detail: detail) { EmptyView() }
    }
}
