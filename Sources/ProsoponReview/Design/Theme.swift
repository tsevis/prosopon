import AppKit
import SwiftUI

/// Prosopon's palette, in the shape the other applications on this machine use.
///
/// The hue is not chosen, it is **measured**. `#E80F9E` is the magenta of the grid ink in
/// `documents/assets/Splash.jpg`, sampled off the lines themselves rather than eyeballed,
/// and every value below is that hue at a different lightness. One knob for the whole
/// interface.
///
/// Two consequences of using it worth writing down.
///
/// White on the brand pink is **4.21:1**, under the 4.5 floor, and the filled button's
/// label is 12pt semibold rather than large text. So `accent` is the same hue four steps
/// darker at 4.55:1, and `brand` stays undiluted for everything that is not carrying
/// type — the icon, the active rule under a stage. Side by side they are the same colour.
///
/// Every value is a *dynamic* `NSColor` rather than a SwiftUI colour picked at read time.
/// Appearance can change under a view already on screen — the system switching at sunset,
/// a window dragged to a display with a different profile — and a value resolved once
/// does not follow.
enum Theme {

    // MARK: - Accent

    /// The splash's own grid ink. Marks, rules and the icon — never type on a fill.
    static let brand = dynamic(light: 0xE80F9E, dark: 0xE80F9E)
    /// Fills and the primary button. White on it clears 4.55:1.
    static let accent = dynamic(light: 0xDE0E97, dark: 0xDE0E97)
    static let accentHover = dynamic(light: 0xF233B1, dark: 0xF233B1)
    /// Type on an accent fill.
    static let accentInk = dynamic(light: 0xFFFFFF, dark: 0xFFFFFF)
    /// The accent used as type: 6.46:1 on white, 5.72:1 on the dark panel.
    static let accentText = dynamic(light: 0xB30C7A, dark: 0xF67BCC)
    /// The tinted ground under a secondary control.
    static let accentSoft = dynamicAlpha(light: (0xB30C7A, 0.10), dark: (0xF67BCC, 0.18))
    static let accentSoftStrong = dynamicAlpha(light: (0xB30C7A, 0.16), dark: (0xF67BCC, 0.26))

    // MARK: - Surfaces

    static let ground = dynamic(light: 0xF5F5F7, dark: 0x1C1C1E)
    static let panel = dynamic(light: 0xFFFFFF, dark: 0x2C2C2E)
    static let inset = dynamic(light: 0xFFFFFF, dark: 0x3A3A3C)
    static let controlTrack = dynamicAlpha(light: (0x767680, 0.12), dark: (0x767680, 0.24))

    /// The ground behind a photograph, and it does **not** follow the appearance.
    ///
    /// A tile is being judged against its neighbours, and a white surround changes what
    /// the eye makes of the shadows in it. Every other image application on this machine
    /// keeps its canvas dark for the same reason.
    static let canvas = Color(white: 0.11)

    // MARK: - Hairlines

    static let hairline = dynamicAlpha(light: (0x3C3C43, 0.16), dark: (0xEBEBF5, 0.13))
    static let hairlineStrong = dynamicAlpha(light: (0x3C3C43, 0.22), dark: (0xEBEBF5, 0.16))

    // MARK: - Type

    static let ink = dynamic(light: 0x1D1D1F, dark: 0xF5F5F7)
    static let inkSecondary = dynamic(light: 0x6E6E73, dark: 0xAEAEB2)
    static let inkTertiary = dynamic(light: 0x8E8E93, dark: 0x8E8E93)

    // MARK: - Banners
    //
    // Two tinted cards, both in the brand hue. They separate by saturation rather than by
    // colour: the settled one is a pale wash of the pink, the unsettled one the same hue
    // drained of it. Every ink clears 7:1 on its own ground.
    //
    // The cost of one hue is real and worth stating: green-means-fine is a convention
    // read without thinking, and pink-means-fine is not. The glyph beside the text and
    // the wording itself are the whole signal.

    /// Nothing is in the way.
    static let noticeFill = dynamic(light: 0xFDEAF7, dark: 0x461034)
    static let noticeBorder = dynamic(light: 0xF5C2E3, dark: 0x7E2560)
    static let noticeInk = dynamic(light: 0x990C69, dark: 0xEF92D0)

    /// Something is.
    static let cautionFill = dynamic(light: 0xF6F1F4, dark: 0x3A2734)
    static let cautionBorder = dynamic(light: 0xE2D4DE, dark: 0x66475C)
    static let cautionInk = dynamic(light: 0x853269, dark: 0xDBABCA)

    // MARK: - Metrics

    enum Radius {
        static let panel: CGFloat = 10
        static let control: CGFloat = 7
        static let thumbnail: CGFloat = 4
    }

    enum Space {
        /// The window's horizontal margin.
        static let workspace: CGFloat = 20
        /// A dialog's horizontal margin.
        static let dialog: CGFloat = 26
    }

    enum Font {
        static let panelTitle = SwiftUI.Font.system(size: 15, weight: .semibold)
        static let body = SwiftUI.Font.system(size: 13)
        static let bodyEmphasis = SwiftUI.Font.system(size: 13, weight: .medium)
        static let support = SwiftUI.Font.system(size: 12)
        static let supportEmphasis = SwiftUI.Font.system(size: 12, weight: .semibold)
        static let meta = SwiftUI.Font.system(size: 11)
        static let metaEmphasis = SwiftUI.Font.system(size: 11, weight: .semibold)
        /// Measurements read as a column, so they are monospaced and lined.
        static let metric = SwiftUI.Font.system(size: 13, design: .monospaced).monospacedDigit()
    }

    // MARK: - Building dynamic colours

    private static func dynamic(light: Int, dark: Int) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.isDark ? NSColor(rgb: dark) : NSColor(rgb: light)
        })
    }

    private static func dynamicAlpha(light: (Int, Double), dark: (Int, Double)) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.isDark
                ? NSColor(rgb: dark.0).withAlphaComponent(dark.1)
                : NSColor(rgb: light.0).withAlphaComponent(light.1)
        })
    }
}

private extension NSAppearance {
    /// `bestMatch` rather than comparing names: the accessibility and high-contrast
    /// appearances have names of their own and are still dark.
    var isDark: Bool { bestMatch(from: [.aqua, .darkAqua]) == .darkAqua }
}

private extension NSColor {
    /// 0xRRGGBB in sRGB, the space these values were measured in.
    convenience init(rgb: Int) {
        self.init(
            srgbRed: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1
        )
    }
}
