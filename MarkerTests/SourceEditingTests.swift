import XCTest
@testable import Marker

/// The step 2c gate. Editing is only worth shipping if what lands on disk is what
/// the user typed and nothing else. A markdown tool that reformats lines the user
/// never touched produces a huge diff on a one-word fix, and that is the fastest
/// way to lose someone's trust in an editor.
nonisolated final class SourceEditingTests: XCTestCase {

    private func document(_ markdown: String) throws -> MarkerDocument {
        let document = MarkerDocument()
        try document.read(from: Data(markdown.utf8), ofType: "net.daringfireball.markdown")
        return document
    }

    func testUnedittedDocumentSavesByteIdentical() throws {
        // Deliberately full of things a formatter would normalise: setext heading,
        // star bullets, ragged table pipes, trailing spaces, tabs, CRLF.
        let original = """
        Setext Heading
        ==============

        * star bullet
        * another

        |a|b|
        |-|-|
        |1|2|

        \ttab indented code

        Hard break line   \r\nnext line
        """
        let document = try document(original)
        let written = try document.data(ofType: "net.daringfireball.markdown")
        XCTAssertEqual(String(data: written, encoding: .utf8), original,
                       "an untouched document must round trip byte for byte")
    }

    func testAnEditChangesOnlyWhatWasEdited() throws {
        let original = "# Title\n\nFirst paragraph.\n\nSecond paragraph.\n"
        let document = try document(original)

        let edited = original.replacingOccurrences(of: "First", with: "Edited")
        document.replaceSource(with: edited)

        let written = try XCTUnwrap(
            String(data: try document.data(ofType: "net.daringfireball.markdown"), encoding: .utf8)
        )
        XCTAssertEqual(written, edited)

        // Every line except the edited one is untouched.
        let before = original.components(separatedBy: "\n")
        let after = written.components(separatedBy: "\n")
        XCTAssertEqual(before.count, after.count)
        let changed = zip(before, after).filter { $0 != $1 }
        XCTAssertEqual(changed.count, 1, "an edit to one line changed \(changed.count) lines")
    }

    func testEditingMarksTheDocumentDirtyAndAnIdenticalWriteDoesNot() throws {
        let document = try document("# Title\n")
        XCTAssertFalse(document.isDocumentEdited)

        document.replaceSource(with: "# Title\n")
        XCTAssertFalse(document.isDocumentEdited, "writing the same text must not dirty the document")

        document.replaceSource(with: "# Changed\n")
        XCTAssertTrue(document.isDocumentEdited)
    }

    // MARK: External change

    func testReloadingPicksUpAnExternalChangeAndClearsTheDirtyFlag() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("marker-reload-\(UUID().uuidString).md")
        try "# Before\n".write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let document = MarkerDocument()
        try document.read(from: Data(contentsOf: url), ofType: "net.daringfireball.markdown")
        document.fileURL = url

        // Local edits, then someone else rewrites the file.
        document.replaceSource(with: "# Before\n\nlocal edit\n")
        XCTAssertTrue(document.isDocumentEdited)

        try "# After\n\nexternal\n".write(to: url, atomically: true, encoding: .utf8)
        try document.reloadFromDisk()

        XCTAssertEqual(document.source.text, "# After\n\nexternal\n")
        XCTAssertFalse(document.isDocumentEdited, "a reload should leave the document clean")
    }

    func testReloadingAMissingFileThrowsRatherThanEmptyingTheDocument() throws {
        // Losing someone's open document because the file moved would be the worst
        // possible response to a rename.
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("marker-gone-\(UUID().uuidString).md")
        try "# Here\n".write(to: url, atomically: true, encoding: .utf8)

        let document = MarkerDocument()
        try document.read(from: Data(contentsOf: url), ofType: "net.daringfireball.markdown")
        document.fileURL = url
        try FileManager.default.removeItem(at: url)

        XCTAssertThrowsError(try document.reloadFromDisk())
        XCTAssertEqual(document.source.text, "# Here\n", "the in-memory document must survive")
    }

    func testMultibyteEditsSurviveTheRoundTrip() throws {
        let original = "# 日本語\n\nnaïve café 👋\n"
        let document = try document(original)
        document.replaceSource(with: original + "\nAppended 👨‍👩‍👧‍👦 line.\n")

        let written = try XCTUnwrap(
            String(data: try document.data(ofType: "net.daringfireball.markdown"), encoding: .utf8)
        )
        XCTAssertTrue(written.hasPrefix(original))
        XCTAssertTrue(written.contains("👨‍👩‍👧‍👦"))
    }
}
