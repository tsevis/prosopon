import ProsoponReview
import SwiftUI

/// There is deliberately no `NSApplicationDelegateAdaptor` here.
///
/// An earlier version installed one to force `setActivationPolicy(.regular)`, which a
/// bare SwiftPM executable needs to behave like an app at all. Once `review.sh` began
/// wrapping the binary in a real `.app` bundle that was already handled — and the
/// adaptor turned out to be actively harmful: with it in place `WindowGroup` created no
/// window on a cold launch. The process sat in its event loop owning a menu bar and
/// nothing else, and only produced a window when something sent it a reopen event,
/// which made it look intermittent rather than broken.
@main
struct ProsoponReviewApp: App {
    /// `prosopon-review ~/aligned` opens that run straight away.
    private static var directoryArgument: URL? {
        let arguments = CommandLine.arguments.dropFirst().filter { !$0.hasPrefix("-") }
        guard let path = arguments.first else { return nil }
        return URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
    }

    var body: some Scene {
        WindowGroup {
            ReviewWindow(directory: Self.directoryArgument)
                // Applied once at the root, so every system control the app has not
                // restyled by hand still lands in the palette rather than defaulting to
                // whichever accent the user has set in System Settings.
                .tint(Theme.tint)
        }
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About \(Brand.name)") {
                    NotificationCenter.default.post(name: .prosoponShowAbout, object: nil)
                }
            }
            CommandGroup(after: .newItem) {
                Button("Add Portraits\u{2026}") {
                    NotificationCenter.default.post(name: .prosoponAddSources, object: nil)
                }
                .keyboardShortcut("i")
            }
            CommandGroup(replacing: .help) {
                Link("Prosopon on GitHub", destination: Brand.repository)
            }
        }
    }
}
