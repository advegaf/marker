import AppKit
import MarkerCore
import MarkerRender
import UniformTypeIdentifiers

/// One open file.
///
/// `NSDocument` is doing real work here rather than being ceremony: it supplies
/// the recent-files menu, multi-window handling, the save pipeline, and the
/// close-with-unsaved-changes sheet, all of which are `/goal` story rows we would
/// otherwise hand-write.
/// Opted out of the project's default MainActor isolation, because NSDocument's
/// own members are nonisolated: AppKit reads a document on a background queue and
/// only guarantees the main thread for the window-creation half. Bridging back is
/// explicit via `MainActor.assumeIsolated`, which traps loudly if that guarantee
/// ever stops holding rather than racing quietly.
nonisolated final class MarkerDocument: NSDocument {

    private(set) var source = MarkdownSource("")

    /// How the file should be presented. Markdown renders; JSON and YAML are
    /// pretty-printed with syntax colours; anything else is plain text.
    enum Presentation {
        case markdown
        case json
        case yaml
        case plainText
    }

    private(set) var presentation: Presentation = .markdown

    override class var autosavesInPlace: Bool { false }

    override func makeWindowControllers() {
        // Documented main-thread entry point.
        MainActor.assumeIsolated {
            addWindowController(DocumentWindowController(document: self))
        }
    }

    override func read(from data: Data, ofType typeName: String) throws {
        guard let text = Self.decode(data) else {
            throw NSError(domain: NSCocoaErrorDomain, code: NSFileReadInapplicableStringEncodingError)
        }
        source = MarkdownSource(text)
        presentation = Self.presentation(forType: typeName, fileExtension: fileURL?.pathExtension)
    }

    override func data(ofType typeName: String) throws -> Data {
        // The raw string is the source of truth, so saving is a straight write
        // with no serialisation step and therefore no reformatting of untouched lines.
        Data(source.text.utf8)
    }

    /// Files in the wild are not all UTF-8. Fall back rather than refusing to open,
    /// since a viewer that cannot open a file has failed at its one job.
    private static func decode(_ data: Data) -> String? {
        if let utf8 = String(data: data, encoding: .utf8) { return utf8 }
        for encoding: String.Encoding in [.utf16, .isoLatin1, .macOSRoman] {
            if let text = String(data: data, encoding: encoding) { return text }
        }
        return nil
    }

    private static func presentation(forType typeName: String, fileExtension: String?) -> Presentation {
        switch fileExtension?.lowercased() {
        case "json": return .json
        case "yaml", "yml": return .yaml
        case "md", "markdown", "mdown", "mkd", "mkdn": return .markdown
        default:
            let type = UTType(typeName)
            if type?.conforms(to: .json) == true { return .json }
            if type?.conforms(to: .yaml) == true { return .yaml }
            if typeName == "net.daringfireball.markdown" { return .markdown }
            return .plainText
        }
    }
}
