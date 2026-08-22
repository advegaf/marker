import SwiftUI

/// The app's motion vocabulary, in one place so no call site invents a duration.
///
/// These live in the app target rather than in `MarkerTheme`, which is the token
/// file for everything else. `MarkerTheme` is AppKit only and is linked into the
/// sandboxed Quick Look extension; putting SwiftUI `Animation` values there would
/// pull SwiftUI into an appex that renders a static image and animates nothing.
/// App chrome motion belongs to the app.
///
/// Every token is a spring with no bounce. There is no timing curve here on
/// purpose: springs are interruptible and carry velocity, and a document viewer
/// has nothing that needs to overshoot.
enum MarkerMotion {

    /// Window-level state, the largest move on screen.
    static let signature = Animation.smooth(duration: 0.44)

    /// A single element settling into place.
    static let micro = Animation.smooth(duration: 0.28)

    /// Push-back on press. Shorter than `micro` because the finger is still down.
    static let press = Animation.smooth(duration: 0.2)

    /// Per-item delay in a staggered entrance.
    static let stagger: Double = 0.045

    /// The reduce-motion substitute: the same end state, no travel, one short
    /// fade. Returning `nil` instead would make elements pop, which reads as a
    /// glitch rather than as restraint.
    static func settle(_ animation: Animation, reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeInOut(duration: 0.2) : animation
    }
}
