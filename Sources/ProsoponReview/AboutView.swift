import AppKit
import SwiftUI

/// What this is, what it refuses to do, and what it owes.
///
/// Shown once at first launch and reachable afterwards from the application menu. Kept to
/// the measurements the other applications on this machine use — 640 x 580, 250pt of
/// full-bleed key art, 26pt margins, 36/13/11 in the lockup, 12.5 body, 10.5 legal — so
/// that opening any of them feels like opening the same program.
///
/// The key art is the program's own output: two half-faces registered onto the same grid,
/// both eyes on the eye line, which is the entire argument the project makes. The one
/// thing a 2.56:1 band cannot hold is the mouth target, 1152 px below the eyes on a 2048
/// square; the eyes are the constraint everything else follows from, so the eyes are what
/// the crop keeps.
public struct AboutView: View {
    /// Supplied by whatever presented it.
    public var close: () -> Void

    public init(close: @escaping () -> Void) { self.close = close }

    @Environment(\.openURL) private var openURL
    @State private var showingLegal = false

    public var body: some View {
        VStack(spacing: 0) {
            keyArt

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(AboutText.story, id: \.self) { paragraph in
                        Text(paragraph)
                            .font(.system(size: 12.5))
                            .lineSpacing(2.5)
                            .foregroundStyle(Theme.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    legalDisclosure
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Theme.Space.dialog)
                .padding(.top, 20)
                .padding(.bottom, 16)
            }
            .scrollBounceBehavior(.basedOnSize)

            footer
        }
        .frame(width: 640, height: 580)
        .background(Theme.panel)
        // Escape and Return both mean "I have read it", matching the close box and the
        // button that does the same thing.
        .onExitCommand(perform: close)
    }

    // MARK: - Key art

    private var keyArt: some View {
        ZStack(alignment: .bottomLeading) {
            // The lockup sits on a photograph, so it brings its own ground: dark at the
            // bottom left where the type is, clear at the top right where the eyes are.
            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.74), location: 0),
                    .init(color: .black.opacity(0.32), location: 0.55),
                    .init(color: .clear, location: 1),
                ],
                startPoint: .bottom, endPoint: .top
            )
            lockup
        }
        .frame(maxWidth: .infinity)
        .frame(height: 250)
        // The photograph is a *background*, not a member of the stack. A `scaledToFill`
        // image inside the ZStack drives the stack to the image's own height, and the
        // lockup then lays out against that oversized frame and lands below the 250pt
        // actually on screen — which cuts the title in half.
        .background {
            if let banner = Brand.banner {
                Image(nsImage: banner)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
            } else {
                LinearGradient(
                    colors: [Color(red: 0.09, green: 0.07, blue: 0.10),
                             Color(red: 0.05, green: 0.03, blue: 0.06)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
            }
        }
        .clipped()
    }

    private var lockup: some View {
        HStack(alignment: .bottom, spacing: 12) {
            Group {
                if let mark = Brand.mark {
                    Image(nsImage: mark).resizable().interpolation(.high)
                } else {
                    RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Theme.accent)
                }
            }
            .frame(width: 49, height: 49)

            VStack(alignment: .leading, spacing: 2) {
                Text(Brand.name)
                    .font(.system(size: 36, weight: .semibold))
                    .tracking(-0.6)
                    // The brand pink undiluted: this is display type on a dark
                    // photograph, not a label on a control.
                    .foregroundStyle(Theme.brand)
                Text(Brand.tagline)
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.85))
            }
            .padding(.bottom, 3)

            Spacer(minLength: 12)

            Text(Brand.version)
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .foregroundStyle(.white.opacity(0.7))
                .padding(.bottom, 3)
        }
        .shadow(color: .black.opacity(0.45), radius: 6, y: 1)
        .padding(.horizontal, Theme.Space.dialog)
        .padding(.bottom, 20)
    }

    // MARK: - Licences

    private var legalDisclosure: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeOut(duration: 0.16)) { showingLegal.toggle() }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .rotationEffect(.degrees(showingLegal ? 90 : 0))
                    Text("Sources, licences and credits")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundStyle(Theme.inkSecondary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if showingLegal {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(AboutText.legal, id: \.self) { paragraph in
                        Text(paragraph)
                            .font(.system(size: 10.5))
                            .lineSpacing(2)
                            .foregroundStyle(Theme.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.top, 2)
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Theme.hairline).frame(height: 1)

            HStack(spacing: 14) {
                Button { openURL(Brand.makerSite) } label: {
                    Text(AboutText.credit)
                        .font(Theme.Font.meta)
                        .foregroundStyle(Theme.inkSecondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .pointerStyle(.link)
                .help(Brand.makerSite.absoluteString)
                .accessibilityLabel("\(AboutText.credit). Opens \(Brand.makerName)'s website.")

                Spacer(minLength: 8)

                Button("Continue", action: close)
                    .buttonStyle(.prosoponPrimary)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, Theme.Space.dialog)
            .padding(.vertical, 12)
            .background(Theme.ground)
        }
    }
}
