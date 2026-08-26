import AppKit
import Foundation

/// The application's own name, version and artwork.
///
/// **Artwork is loaded by URL, never by `Image("name", bundle: .module)`.** Nino hit this
/// and recorded it: the asset-catalogue accessor came back empty against a SwiftPM
/// resource, the splash rendered as a bare gradient, and every assertion about the layout
/// still passed because a missing image is a valid `Image`. `Bundle.module.url(...)`
/// returns a real file or nothing, and `BrandTests` fails when it is nothing.
///
/// Which makes the second half of the rule matter as much: these are `Optional` and the
/// views fall back visibly, so a resource that stops being copied shows up as a plain
/// gradient in the panel *and* as a red test, rather than only the former.
public enum Brand {
    public static let name = "Prosopon"
    public static let tagline = "Portraits on one fixed face grid."
    public static let version = "0.4.2"

    public static let makerName = "Charis Tsevis"
    public static let makerSite = URL(string: "https://www.tsevis.com")!
    public static let makerSiteLabel = "tsevis.com"
    public static let githubSite = URL(string: "https://github.com/tsevis")!
    public static let githubLabel = "github.com/tsevis"
    public static let repository = URL(string: "https://github.com/tsevis/prosopon")!

    /// The 640 x 250 key art: two half-faces on the canonical grid, both eyes on the eye
    /// line. Cropped from `documents/assets/Splash.jpg` by `scripts/make_assets.py`.
    public static let banner = image(named: "AboutBanner", extension: "jpg")

    /// The icon, for the lockup that sits on the banner.
    public static let mark = image(named: "AppMark", extension: "png")

    /// `nil` rather than a placeholder, so a missing file is visible to a test.
    static func image(named name: String, extension ext: String) -> NSImage? {
        guard let url = resourceURL(named: name, extension: ext) else { return nil }
        return NSImage(contentsOf: url)
    }

    static func resourceURL(named name: String, extension ext: String) -> URL? {
        Bundle.module.url(forResource: "Resources/\(name)", withExtension: ext)
            ?? Bundle.module.url(forResource: name, withExtension: ext)
    }
}
