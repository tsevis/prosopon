import AppKit
import ProsoponReview
import SwiftUI

/// A SwiftPM executable launches without a bundle, so it starts as a background process
/// with no menu bar and no focus. Promoting it here is what makes it behave like an app.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main
struct ProsoponReviewApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

    /// `prosopon-review ~/aligned` opens that run straight away.
    private static var directoryArgument: URL? {
        let arguments = CommandLine.arguments.dropFirst().filter { !$0.hasPrefix("-") }
        guard let path = arguments.first else { return nil }
        return URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
    }

    var body: some Scene {
        WindowGroup {
            ReviewWindow(directory: Self.directoryArgument)
        }
        .windowResizability(.contentMinSize)
    }
}
