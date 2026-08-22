import AppKit

/// Explicit entry point rather than `@main` on the delegate.
///
/// The snapshot path has to run before AppKit's run loop starts, not from
/// `applicationDidFinishLaunching`, so that rendering a PNG never depends on the
/// app finishing a normal launch. It also lets the process stay activation-policy
/// prohibited, so a QA run never steals focus from whoever is at the keyboard.
/// Launch-time concerns that only exist for the QA harness.
enum Harness {

    static var isActive: Bool {
        ProcessInfo.processInfo.environment.keys.contains { $0.hasPrefix("MARKER_") }
    }

    /// Throws away any saved window state before the app starts.
    ///
    /// `isRestorable = false` only stops state being *written*; windows saved by an
    /// earlier run still come back. Under the harness that meant several windows
    /// open on the same fixture, each acting on the launch flags, compounding edits
    /// on one shared document and reporting a result from the wrong one. It looked
    /// exactly like the feature under test misbehaving.
    static func suppressWindowRestorationIfNeeded() {
        guard isActive else { return }
        let bundleID = Bundle.main.bundleIdentifier ?? "com.advegaf.Marker"
        let saved = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Saved Application State/\(bundleID).savedState")
        try? FileManager.default.removeItem(at: saved)
    }
}

@main
enum Main {

    static func main() {
        let app = NSApplication.shared
        Harness.suppressWindowRestorationIfNeeded()

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
