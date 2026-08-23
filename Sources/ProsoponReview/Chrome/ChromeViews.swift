import SwiftUI

/// The window's three strips: which stage, what can be done here, and how it is going.
///
/// Deliberately thin. Every string and every dimmed control comes from `Stage`,
/// `CommandSet` and `StatusBanner`, which are values with tests; what is left in this
/// file is arrangement, and arrangement is the part a test could not check anyway.

// MARK: - The stage strip

struct StageStrip: View {
    @Binding var selection: Stage
    let state: ChromeState

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Stage.allCases) { stage in
                StageTab(
                    stage: stage,
                    isActive: selection == stage,
                    badge: stage.badge(state),
                    help: stage.help(state)
                ) {
                    selection = stage
                }
            }

            Spacer(minLength: 16)

            StatusChip(symbol: "lock.shield.fill", text: "On this Mac only")
                .help("Face detection, alignment and every photograph stay on this "
                    + "machine. Nothing is uploaded and no account is needed.")
        }
        .padding(.horizontal, Theme.Space.workspace)
        .frame(height: 48)
        .background(Theme.panel)
    }
}

private struct StageTab: View {
    let stage: Stage
    let isActive: Bool
    let badge: Int?
    let help: String
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: stage.symbol)
                    .font(.system(size: 12, weight: isActive ? .semibold : .regular))
                Text(stage.label)
                    .font(.system(size: 13, weight: isActive ? .semibold : .medium))
                if let badge {
                    CountBadge(count: badge, tint: isActive ? Theme.accentText : Theme.inkTertiary)
                }
            }
            .foregroundStyle(
                isActive ? Theme.accentText : (hovering ? Theme.ink : Theme.inkSecondary)
            )
            .padding(.horizontal, 13)
            .frame(height: 48)
            // A rule under the tab rather than a pill around it: at this size a pill
            // crowds the badge beside it. An overlay rather than a VStack sibling,
            // because a Rectangle has no intrinsic width and stacked under the label it
            // expands to fill the row and drags the tabs apart.
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(isActive ? Theme.brand : .clear)
                    .frame(height: 2)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
    }
}

// MARK: - The command bar

/// One full-width line: what is loaded on the left, what to do about it on the right.
///
/// Every action available on this stage is here and nowhere else. No panel carries its
/// own private set of buttons, which is what keeps a window with three stages and a dozen
/// actions still reading as simple.
struct CommandBar<Leading: View>: View {
    let commands: [Command]
    let perform: (ChromeAction) -> Void
    @ViewBuilder var leading: Leading

    var body: some View {
        HStack(spacing: 8) {
            leading
            Spacer(minLength: 16)
            ForEach(commands) { command in
                CommandButton(command: command) { perform(command.action) }
            }
        }
        .padding(.horizontal, Theme.Space.workspace)
        .frame(height: 52)
        .background(Theme.ground)
        .overlay(alignment: .top) { Rectangle().fill(Theme.hairline).frame(height: 1) }
    }
}

private struct CommandButton: View {
    let command: Command
    let action: () -> Void

    var body: some View {
        let label = Label(command.title, systemImage: command.symbol)
            .labelStyle(.titleAndIcon)

        Group {
            switch command.weight {
            case .primary: Button(action: action) { label }.buttonStyle(.prosoponPrimary)
            case .secondary: Button(action: action) { label }.buttonStyle(.prosoponSecondary)
            case .quiet: Button(action: action) { label }.buttonStyle(.prosoponQuiet)
            }
        }
        .disabled(!command.isEnabled)
        .help(command.help)
    }
}

// MARK: - The subject chip

/// What is loaded and how far along it is — the line somebody glances at to know which
/// batch they are in the middle of.
struct SubjectChipView: View {
    let state: ChromeState
    let onOpenRun: () -> Void
    let onRevealRun: () -> Void

    var body: some View {
        Menu {
            Button("Open Run\u{2026}", action: onOpenRun)
            Button("Reveal in Finder", action: onRevealRun)
                .disabled(!state.hasRun)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: SubjectChip.symbol).foregroundStyle(Theme.accentText)
                VStack(alignment: .leading, spacing: 1) {
                    Text(SubjectChip.title(state))
                        .font(Theme.Font.supportEmphasis)
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                    if let detail = SubjectChip.detail(state) {
                        Text(detail)
                            .font(Theme.Font.meta)
                            .foregroundStyle(Theme.inkSecondary)
                            .lineLimit(1)
                    }
                }
            }
            .frame(maxWidth: 260, alignment: .leading)
        }
        // `.button` deliberately: `.borderlessButton` draws the label but stops the menu
        // taking clicks.
        .menuStyle(.button)
        .buttonStyle(.prosoponQuiet)
        .fixedSize()
        .help("What is loaded, and how far along it is")
    }
}

// MARK: - The banner

struct BannerView: View {
    let banner: StatusBanner

    private var ink: Color { banner.kind == .notice ? Theme.noticeInk : Theme.cautionInk }
    private var fill: Color { banner.kind == .notice ? Theme.noticeFill : Theme.cautionFill }
    private var border: Color {
        banner.kind == .notice ? Theme.noticeBorder : Theme.cautionBorder
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 9) {
            Image(systemName: banner.symbol)
                .font(.system(size: 11))
                .foregroundStyle(ink)
            Text(banner.text)
                .font(Theme.Font.meta)
                .foregroundStyle(ink)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            if !banner.extra.isEmpty {
                CountBadge(count: banner.extra.count, tint: ink)
                    .help(banner.extra.joined(separator: "\n"))
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(fill)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                .strokeBorder(border, lineWidth: 1)
        )
        .padding(.horizontal, Theme.Space.workspace)
        .padding(.top, 10)
    }
}

// MARK: - Progress

/// A long run keeps its place on screen while it runs, wherever the reviewer wanders.
struct AnalysisProgressStrip: View {
    let state: ChromeState

    var body: some View {
        if state.isAnalysing, let progress = state.progress {
            HStack(spacing: 10) {
                ProgressView(value: progress.fraction)
                    .progressViewStyle(.linear)
                    .tint(Theme.accent)
                Text("\(progress.completed)/\(progress.total)")
                    .font(Theme.Font.meta.monospacedDigit())
                    .foregroundStyle(Theme.inkSecondary)
            }
            .padding(.horizontal, Theme.Space.workspace)
            .padding(.top, 8)
        }
    }
}
