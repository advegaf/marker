import AppKit
import MarkerRender

final class MarkerApp: NSObject, NSApplicationDelegate {

    /// Documents ask for this rather than owning a theme each, so switching
    /// appearance updates every open window from one place.
    static let appearance = AppearanceController()

    /// Set for the launch that showed the walkthrough, so the open panel stays out
    /// of its way. Not persisted: it is about this launch, not this install.
    private var presentedWelcome = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        MainMenu.install()
        Self.appearance.applyToApplication()
        openFileFromLaunchEnvironmentIfNeeded()
        if WelcomeWindowController.shouldShowAtLaunch {
            // Closing the window with the red button counts as having seen it, the
            // same as either of its own buttons. Otherwise it comes back on every
            // launch until someone presses the right thing.
            Preferences.hasSeenWelcome = true
            presentedWelcome = true
            WelcomeWindowController.shared.showWindow(nil)
            if let window = WelcomeWindowController.shared.window {
                WindowSnapshot.holdIfRequested(window: window)
            }
        }
        if ProcessInfo.processInfo.environment["MARKER_SETTINGS"] != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                SettingsWindowController.shared.showWindow(nil)
            }
        }

        if ProcessInfo.processInfo.environment["MARKER_DEBUG_WINDOWS"] != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                let lines = NSApp.windows.map {
                    "  visible=\($0.isVisible) frame=\($0.frame) title=\($0.title) screen=\($0.screen != nil)"
                }
                FileHandle.standardError.write(Data((
                    "[dbg] windows=\(NSApp.windows.count)\n" + lines.joined(separator: "\n") + "\n"
                ).utf8))
                exit(0)
            }
        }
    }

    // MARK: Menu actions

    @objc func selectAppearance(_ sender: NSMenuItem) {
        let choices = MarkerTheme.Appearance.allCases
        guard choices.indices.contains(sender.tag) else { return }
        Self.appearance.set(choices[sender.tag])
    }

    @objc func showSettings(_ sender: Any?) {
        SettingsWindowController.shared.showWindow(sender)
    }

    @objc func showWelcome(_ sender: Any?) {
        WelcomeWindowController.shared.showWindow(sender)
    }

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        // A viewer with no document should show the open panel, not a blank page.
        // Never under XCTest: the panel is modal, so it parks the run loop and the
        // test host hangs until something kills it.
        // Not on the launch that shows the walkthrough. A modal open panel over
        // the welcome window means the first thing a new user sees is a file
        // browser covering the thing explaining the app.
        //
        // Both halves are needed because AppKit does not guarantee this is asked
        // after `applicationDidFinishLaunching`. Asked first, the stored key has
        // not been written yet and `shouldShowAtLaunch` is the one that answers;
        // asked second, the key is already set and `presentedWelcome` is. Checking
        // only the flag shipped a build where the panel opened over the welcome
        // window anyway.
        guard !presentedWelcome, !WelcomeWindowController.shouldShowAtLaunch else { return false }
        let environment = ProcessInfo.processInfo.environment
        return environment["MARKER_OPEN"] == nil
            && environment["XCTestConfigurationFilePath"] == nil
            && environment["XCTestBundlePath"] == nil
    }

    func applicationOpenUntitledFile(_ sender: NSApplication) -> Bool {
        NSDocumentController.shared.openDocument(nil)
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// `MARKER_OPEN` is how the QA harness drives the app into a known state
    /// without a UI script. It is read once, at launch, and never persisted.
    private func openFileFromLaunchEnvironmentIfNeeded() {
        guard let path = ProcessInfo.processInfo.environment["MARKER_OPEN"] else { return }
        let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { document, _, error in
            if WindowSnapshot.isRequested {
                guard let controller = document?.windowControllers
                    .compactMap({ $0 as? DocumentWindowController }).first else {
                    FileHandle.standardError.write(Data("MARKER_WINDOW_SNAPSHOT: no window for \(url.path)\n".utf8))
                    exit(1)
                }
                controller.captureForHarness()
            }
            if let error {
                FileHandle.standardError.write(
                    Data("MARKER_OPEN failed for \(url.path): \(error.localizedDescription)\n".utf8)
                )
                exit(1)
            }
        }
    }
}
