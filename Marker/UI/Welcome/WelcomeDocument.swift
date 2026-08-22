import AppKit

/// The bundled welcome document, and the copy of it the reader actually opens.
///
/// Editing is free, so this is the first file a new user is likely to press Edit
/// on. Opening it straight out of `Marker.app/Contents/Resources` would mean the
/// first save either fails on permissions or, worse, succeeds and invalidates the
/// app's code signature. So the bundle copy is a template and never opened.
enum WelcomeDocument {

    private static let filename = "Welcome to Marker.md"

    /// `~/Library/Application Support/Marker/Welcome to Marker.md`.
    static var destination: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("Marker", isDirectory: true)
            .appendingPathComponent(filename)
    }

    /// Copies the template out on first use, then opens the copy.
    ///
    /// An existing copy is left alone. Someone who edited it and comes back through
    /// the Help menu should find their own version, not have it overwritten by the
    /// one in the bundle.
    static func open() {
        guard let url = materialize() else {
            NSSound.beep()
            return
        }
        NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, error in
            if let error { NSApp.presentError(error) }
        }
    }

    static func materialize() -> URL? {
        let target = destination
        if FileManager.default.fileExists(atPath: target.path) { return target }

        guard let template = Bundle.main.url(forResource: "Welcome to Marker", withExtension: "md") else {
            return nil
        }
        do {
            try FileManager.default.createDirectory(
                at: target.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try FileManager.default.copyItem(at: template, to: target)
            return target
        } catch {
            return nil
        }
    }
}
