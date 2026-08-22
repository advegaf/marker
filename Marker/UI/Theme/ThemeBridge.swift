import Foundation
import MarkerRender

/// Publishes the chosen theme where the Quick Look extension can read it.
///
/// The extension has to be sandboxed, because macOS refuses to register a Quick
/// Look preview that is not, and a sandboxed extension cannot read the host app's
/// preferences. An app group would be the textbook answer, but app groups need a
/// provisioning profile this ad-hoc signed build does not have.
///
/// What does work: the app is unsandboxed, so it can write into the extension's own
/// container, and the extension is always allowed to read that. One small file,
/// written whenever the theme changes.
enum ThemeBridge {

    private static let extensionBundleID = "com.advegaf.Marker.QuickLook"

    static var sharedFile: URL {
        URL(fileURLWithPath: NSHomeDirectory())
            // NSHomeDirectory is the real home here, since the app is not sandboxed.
            .appendingPathComponent("Library/Containers/\(extensionBundleID)/Data/Library/Application Support")
            .appendingPathComponent("marker-theme.json")
    }

    static func publish(_ appearance: MarkerTheme.Appearance) {
        let payload = ["appearance": appearance.rawValue]
        guard let data = try? JSONSerialization.data(withJSONObject: payload) else { return }
        let file = sharedFile
        try? FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        // Failure is not worth reporting: the preview falls back to the system
        // appearance, which is a reasonable answer rather than a broken one.
        try? data.write(to: file, options: .atomic)
    }
}
