import SwiftUI

/// The handful of controls the chrome is built from.
///
/// Three button weights and no more, because the toolbar's whole job is to say which
/// action is the one to take. Exactly one filled control per stage: an accent used twice
/// is an accent used nowhere.

// MARK: - Buttons

/// The one thing to do next. Pressed, it keeps its colour and moves instead of dimming.
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.Font.supportEmphasis)
            .foregroundStyle(Theme.accentInk)
            .padding(.horizontal, 13)
            .padding(.vertical, 7)
            .background(configuration.isPressed ? Theme.accentHover : Theme.accent)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
            .opacity(isEnabled ? 1 : 0.45)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Available and worth noticing, but not the point of the screen.
struct SecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.Font.supportEmphasis)
            .foregroundStyle(Theme.accentText)
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background(configuration.isPressed ? Theme.accentSoftStrong : Theme.accentSoft)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
            .opacity(isEnabled ? 1 : 0.45)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// The quietest weight. Everything that should be reachable without competing.
///
/// Unavailable actions use this at 45% rather than disappearing: a control that vanishes
/// takes the knowledge that it exists with it.
struct QuietButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    var role: ButtonRole?

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.Font.supportEmphasis)
            .foregroundStyle(role == .destructive ? Theme.cautionInk : Theme.inkSecondary)
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background(configuration.isPressed ? Theme.controlTrack : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                    .strokeBorder(Theme.hairlineStrong, lineWidth: 1)
            )
            .opacity(isEnabled ? 1 : 0.45)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// A square for a single glyph — the queue's arrows, an inspector toggle.
struct IconButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    var size: CGFloat = 28

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: size * 0.45))
            .foregroundStyle(Theme.ink)
            .frame(width: size, height: size)
            .background(configuration.isPressed ? Theme.accentSoft : Theme.controlTrack)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
            .opacity(isEnabled ? 1 : 0.45)
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var prosoponPrimary: Self { PrimaryButtonStyle() }
}

extension ButtonStyle where Self == SecondaryButtonStyle {
    static var prosoponSecondary: Self { SecondaryButtonStyle() }
}

extension ButtonStyle where Self == QuietButtonStyle {
    static var prosoponQuiet: Self { QuietButtonStyle() }
    static func prosoponQuiet(role: ButtonRole?) -> Self { QuietButtonStyle(role: role) }
}

extension ButtonStyle where Self == IconButtonStyle {
    static var prosoponIcon: Self { IconButtonStyle() }
}

// MARK: - Small pieces

/// A count on a tinted pill, beside the stage it belongs to.
struct CountBadge: View {
    let count: Int
    var tint: Color = Theme.accentText

    var body: some View {
        Text("\(count)")
            .font(Theme.Font.meta.monospacedDigit())
            .foregroundStyle(tint)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .frame(minWidth: 18)
            .background(tint.opacity(0.14), in: Capsule())
    }
}

/// The one piece of chrome that states what the program promises, so it stays on screen
/// rather than living in a menu.
struct StatusChip: View {
    let symbol: String
    let text: String
    var tint: Color = Theme.accentText

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol).foregroundStyle(tint)
            Text(text).foregroundStyle(Theme.inkSecondary)
        }
        .font(Theme.Font.meta)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(
            Theme.controlTrack,
            in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
        )
    }
}

/// What to show where the work would be, when there is none yet.
struct EmptyStateView<Actions: View>: View {
    let symbol: String
    let title: String
    let message: String
    @ViewBuilder var actions: Actions

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(Theme.accentText.opacity(0.7))
            Text(title)
                .font(Theme.Font.panelTitle)
                .foregroundStyle(Theme.ink)
            Text(message)
                .font(Theme.Font.support)
                .foregroundStyle(Theme.inkSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
                .fixedSize(horizontal: false, vertical: true)
            actions.padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }
}

extension EmptyStateView where Actions == EmptyView {
    init(symbol: String, title: String, message: String) {
        self.init(symbol: symbol, title: title, message: message) { EmptyView() }
    }
}
