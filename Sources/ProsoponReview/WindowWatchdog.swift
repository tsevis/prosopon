import AppKit
import Foundation

/// What to do about a launch that produced no window.
enum WindowRemedy: Equatable {
    /// The launch worked. Touch nothing.
    case none
    /// A window object exists but is not on screen. Order it front — do **not** ask for
    /// another, or the launch that was merely slow ends up with two.
    case presentExistingWindow
    /// There is no window at all. Send the event a Dock-icon click sends; SwiftUI's own
    /// delegate answers it by building the missing one.
    case reopen
}

/// Makes sure the app that launched actually put a window on screen.
///
/// `WindowGroup` does not always create its window on a cold launch. The process comes
/// up, owns a menu bar, sits in its event loop at zero percent, and shows nothing.
/// Measured here by killing the previous instance and starting a new one straight after:
/// 2 failures in 10 launches before this, 0 in 20 after. It is the fourth recorded cause
/// of this project's one recurring symptom (docs/PLAN.md section 12) and the one that
/// outlived the other three being fixed.
///
/// Two different things go wrong and they need different answers, which is why the first
/// version of this only cut the rate to 1 in 20 rather than removing it: usually no
/// window is built at all, and a reopen event builds one — but sometimes a window exists
/// and was never ordered on screen, and reopen does nothing for that because SwiftUI can
/// see it already has one.
///
/// **Deliberately not an `NSApplicationDelegateAdaptor`.** Installing one to force
/// `setActivationPolicy(.regular)` is what made this failure permanent rather than
/// intermittent — see the note in `ProsoponReviewApp`. This takes no delegate, changes no
/// activation policy, and does nothing at all on a launch that worked.
public enum WindowWatchdog {

    /// When to look. Spread out because the failure is a race, and a launch that is
    /// merely slow must be given time rather than interrupted.
    static let checkpoints: [TimeInterval] = [0.8, 1.8, 3.0, 4.5]

    /// The rule, separated from AppKit so it can be tested without a window server.
    ///
    /// Order matters: a window that exists but is not on screen must be presented, never
    /// reopened, since asking SwiftUI for a window while it holds one it never showed is
    /// how an app ends up with two.
    static func remedy(hasVisibleWindow: Bool, hasAnyContentWindow: Bool) -> WindowRemedy {
        if hasVisibleWindow { return .none }
        if hasAnyContentWindow { return .presentExistingWindow }
        return .reopen
    }

    /// Starts watching. Call once, before the scene is built.
    @MainActor
    public static func start() {
        for delay in checkpoints {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { check() }
        }
    }

    @MainActor
    static func check() {
        guard let app = NSApp else { return }
        let content = app.windows.filter { $0.contentView != nil }
        switch remedy(
            hasVisibleWindow: content.contains(where: \.isVisible),
            hasAnyContentWindow: !content.isEmpty
        ) {
        case .none:
            return
        case .presentExistingWindow:
            content.first?.makeKeyAndOrderFront(nil)
        case .reopen:
            _ = app.delegate?.applicationShouldHandleReopen?(app, hasVisibleWindows: false)
        }
    }
}
