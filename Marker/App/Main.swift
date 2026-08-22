import AppKit

/// Explicit entry point rather than `@main` on the delegate.
///
/// The snapshot path has to run before AppKit's run loop starts, not from
/// `applicationDidFinishLaunching`, so that rendering a PNG never depends on the
/// app finishing a normal launch. It also lets the process stay activation-policy
/// prohibited, so a QA run never steals focus from whoever is at the keyboard.
@main
enum Main {

    static func main() {
        let app = NSApplication.shared

        if ProcessInfo.processInfo.environment["MARKER_SNAPSHOT"] != nil {
            app.setActivationPolicy(.prohibited)
            ScreenshotHarness.runIfRequested()  // renders, writes, exits
            return
        }

        let delegate = MarkerApp()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
        withExtendedLifetime(delegate) {}
    }
}
