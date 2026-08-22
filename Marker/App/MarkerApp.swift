import AppKit
import MarkerRender

final class MarkerApp: NSObject, NSApplicationDelegate {

    /// Documents ask for this rather than owning a theme each, so switching
    /// appearance updates every open window from one place.
    static let appearance = AppearanceController()

    /// One store for the whole app. The trial clock and the stored licence are
    /// process-wide facts, not per-document ones.
    static let license = LicenseStore()

    func applicationDidFinishLaunching(_ notification: Notification) {
        MainMenu.install()
        Self.appearance.applyToApplication()
        openFileFromLaunchEnvironmentIfNeeded()
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

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        // A viewer with no document should show the open panel, not a blank page.
        // Never under XCTest: the panel is modal, so it parks the run loop and the
        // test host hangs until something kills it.
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
