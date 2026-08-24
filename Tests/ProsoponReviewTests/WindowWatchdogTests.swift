import Testing
@testable import ProsoponReview

/// The rule the watchdog applies, without a window server.
///
/// Only the decision is tested. Carrying it out needs a running application, and a test
/// that made one would put a window on somebody's screen — see the note on
/// `WindowWatchdog` for what it is actually for.
@Suite("Window watchdog")
struct WindowWatchdogTests {

    @Test("a launch that produced a window is left alone")
    func doesNothingWhenAWindowIsOnScreen() {
        #expect(WindowWatchdog.remedy(hasVisibleWindow: true, hasAnyContentWindow: true) == .none)
    }

    @Test("no window at all is answered by asking for one")
    func reopensWhenThereIsNoWindow() {
        #expect(WindowWatchdog.remedy(hasVisibleWindow: false, hasAnyContentWindow: false) == .reopen)
    }

    @Test("a window that exists but was never shown is put on screen, not duplicated")
    func presentsAWindowThatWasNeverOrderedFront() {
        // The case the first version of this missed, and why it only cut the failures
        // rather than removing them: reopen does nothing when SwiftUI can see it already
        // holds a window, however invisible that window is.
        #expect(
            WindowWatchdog.remedy(hasVisibleWindow: false, hasAnyContentWindow: true)
                == .presentExistingWindow
        )
    }

    @Test("it looks more than once, because the failure is a race")
    func checksRepeatedly() {
        #expect(WindowWatchdog.checkpoints.count >= 2)
        #expect(WindowWatchdog.checkpoints == WindowWatchdog.checkpoints.sorted())
        #expect(WindowWatchdog.checkpoints.first ?? 0 > 0, "not before the launch has had a chance")
    }
}
