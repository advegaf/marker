import AppKit
import MarkerCore
import MarkerRender

/// `MARKER_SNAPSHOT=<out.png>` renders one document offscreen and exits.
///
/// Runs before any window is made, so the app never appears, never steals focus,
/// and never needs Screen Recording permission. Exit code is meaningful so a QA
/// script can tell a render failure from a missing file.
enum ScreenshotHarness {

    static func runIfRequested() {
        let environment = ProcessInfo.processInfo.environment
        guard let outputPath = environment["MARKER_SNAPSHOT"] else { return }

        guard let inputPath = environment["MARKER_OPEN"] else {
            fail("MARKER_SNAPSHOT needs MARKER_OPEN to say which file to render")
        }

        let inputURL = URL(fileURLWithPath: (inputPath as NSString).expandingTildeInPath)
        guard let data = try? Data(contentsOf: inputURL),
              let text = String(data: data, encoding: .utf8) else {
            fail("could not read \(inputURL.path)")
        }

        let appearance = environment["MARKER_THEME"]
            .flatMap(MarkerTheme.Appearance.init(rawValue:)) ?? .light
        let zoom = ZoomController.clamp(
            environment["MARKER_ZOOM"].flatMap { Double($0) }.map { CGFloat($0) } ?? 1.0
        )
        let width = environment["MARKER_WIDTH"].flatMap { Double($0) }.map { CGFloat($0) } ?? 1200

        let theme = MarkerTheme.standard(appearance, zoom: zoom)
        guard let png = OffscreenRenderer.png(
            of: MarkdownSource(text),
            theme: theme,
            options: .init(width: width)
        ) else {
            fail("offscreen render produced no image")
        }

        let outputURL = URL(fileURLWithPath: (outputPath as NSString).expandingTildeInPath)
        do {
            try FileManager.default.createDirectory(
                at: outputURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try png.write(to: outputURL)
        } catch {
            fail("could not write \(outputURL.path): \(error.localizedDescription)")
        }

        FileHandle.standardOutput.write(Data("\(outputURL.path)\n".utf8))
        exit(0)
    }

    private static func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data("MARKER_SNAPSHOT: \(message)\n".utf8))
        exit(1)
    }
}
