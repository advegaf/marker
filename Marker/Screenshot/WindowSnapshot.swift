import AppKit

/// `MARKER_WINDOW_SNAPSHOT=<out.png>` captures the real window and exits.
///
/// Distinct from `MARKER_SNAPSHOT`, and the distinction is the point. The offscreen
/// path proves what the renderer produces; it cannot prove anything about the
/// window, which is how a scroll bug survived a passing screenshot. Anything about
/// the toolbar, the scroll view, the find bar, resize or edit mode is captured here
/// instead, against a window that is actually on screen.
///
/// Known limits, stated rather than discovered later: this orders the window front,
/// so it does take focus, and `cacheDisplay` re-renders the view tree rather than
/// reading the window server, so Liquid Glass and other vibrancy come out
/// approximated. Rows about glass specifically use `screencapture -l <windowid>`.
enum WindowSnapshot {

    static var isRequested: Bool {
        let environment = ProcessInfo.processInfo.environment
        return environment["MARKER_WINDOW_SNAPSHOT"] != nil || environment["MARKER_WINDOW_HOLD"] != nil
    }

    /// Called once the document window exists. Waits for one layout pass, applies
    /// any requested scroll, captures, reports metrics on stdout, then exits.
    static func captureThenExit(controller: DocumentViewController, window: NSWindow) {
        let environment = ProcessInfo.processInfo.environment
        let outputPath = environment["MARKER_WINDOW_SNAPSHOT"]
        let holds = environment["MARKER_WINDOW_HOLD"] != nil
        guard outputPath != nil || holds else { return }

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        // One turn of the run loop so layout, the toolbar and the scroll view have
        // all settled before anything is measured or drawn.
        DispatchQueue.main.async {
            if let edge = environment["MARKER_SCROLL"].flatMap(DocumentViewController.ScrollEdge.init(rawValue:)) {
                controller.scroll(to: edge)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                let metrics = controller.scrollMetrics
                // Reported so a QA run can assert on numbers, not only on pixels.
                let line = "document=\(Int(metrics.document)) visible=\(Int(metrics.visible)) offset=\(Int(metrics.offset)) \(controller.diagnostics)"
                FileHandle.standardOutput.write(Data((line + "\n").utf8))

                // MARKER_WINDOW_HOLD hands the window number to the caller and stays
                // alive so `screencapture -l` can shoot the real thing.
                //
                // Neither in-process path can capture this window. `cacheDisplay`
                // re-renders the view tree and TextKit 2 draws its fragments into
                // CALayers it never visits; `dataWithPDF` goes through the same layer
                // path. Both produce a perfectly framed window with an empty page in
                // it, which is worse than no screenshot, because it reads as a
                // rendering bug rather than a capture bug. The window server is the
                // only thing that sees what is actually on screen.
                if holds {
                    FileHandle.standardOutput.write(
                        Data("windownumber=\(window.windowNumber)\n".utf8)
                    )
                    return
                }

                guard let frameView = window.contentView?.superview,
                      let png = image(of: frameView) else {
                    FileHandle.standardError.write(Data("MARKER_WINDOW_SNAPSHOT: capture failed\n".utf8))
                    exit(1)
                }
                let url = URL(fileURLWithPath: ((outputPath ?? "") as NSString).expandingTildeInPath)
                do {
                    try FileManager.default.createDirectory(
                        at: url.deletingLastPathComponent(), withIntermediateDirectories: true
                    )
                    try png.write(to: url)
                } catch {
                    FileHandle.standardError.write(
                        Data("MARKER_WINDOW_SNAPSHOT: \(error.localizedDescription)\n".utf8)
                    )
                    exit(1)
                }
                FileHandle.standardOutput.write(Data("\(url.path)\n".utf8))
                exit(0)
            }
        }
    }

    /// Captures through PDF rather than `cacheDisplay`.
    ///
    /// `cacheDisplay` re-renders the view tree, and TextKit 2 inside a scroll view
    /// draws its layout fragments into CALayers that the re-render does not visit.
    /// The result is a perfectly framed window with an empty page in it, which is a
    /// worse failure than no screenshot at all because it looks like a rendering bug.
    /// `dataWithPDF(inside:)` drives `draw(_:)` for the whole tree, so the text is
    /// really there, and rasterising it at 2x keeps the output machine independent.
    private static func image(of view: NSView) -> Data? {
        let bounds = view.bounds
        guard bounds.width > 1, bounds.height > 1 else { return nil }

        let pdf = view.dataWithPDF(inside: bounds)
        guard let page = NSPDFImageRep(data: pdf) else { return nil }

        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(bounds.width * 2), pixelsHigh: Int(bounds.height * 2),
            bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else { return nil }
        rep.size = bounds.size

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor.white.setFill()
        bounds.fill()
        page.draw(in: bounds)
        NSGraphicsContext.restoreGraphicsState()

        return rep.representation(using: .png, properties: [:])
    }
}
