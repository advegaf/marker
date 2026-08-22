import Testing
import AppKit
import MarkerCore
@testable import MarkerRender

// The hinge of WYSIWYG editing. Every test here is a keystroke someone will
// actually make, and the ones that matter most are the refusals: a mapping that
// guesses is how a file gets corrupted.

private struct Editor {
    var source: MarkdownSource
    var index: BlockIndex
    var rendered: String

    init(_ markdown: String) {
        source = MarkdownSource(markdown)
        let document = DocumentRenderer(theme: .standard(.light), mode: .image).renderDocument(source)
        index = document.index
        rendered = document.attributed.string
    }

    /// Where `needle` sits in the rendered string, in UTF-16 offsets.
    func renderOffset(of needle: String) -> Int {
        (rendered as NSString).range(of: needle).location
    }

    func map(_ range: Range<Int>, _ replacement: String) -> Result<EditMapper.Mapped, EditMapper.Refusal> {
        EditMapper.map(renderRange: range, replacement: replacement, index: index, source: source)
    }

    /// Applies a mapped edit and returns the resulting source text.
    func applying(_ range: Range<Int>, _ replacement: String) throws -> String {
        let mapped = try map(range, replacement).get()
        var copy = source
        copy.apply(mapped.edit)
        return copy.text
    }
}

@Test @MainActor func typingInsideAParagraphLandsInTheRightPlace() throws {
    let editor = Editor("Hello world.")
    let offset = editor.renderOffset(of: "world")
    #expect(try editor.applying(offset ..< offset, "brave ") == "Hello brave world.")
}

@Test @MainActor func typingAtTheEndOfAParagraphAppends() throws {
    let editor = Editor("Hello")
    let end = (editor.rendered as NSString).length
    #expect(try editor.applying(end ..< end, "!") == "Hello!")
}

@Test @MainActor func deletingASelectionRemovesExactlyThoseBytes() throws {
    let editor = Editor("Hello brave world.")
    let start = editor.renderOffset(of: "brave ")
    #expect(try editor.applying(start ..< (start + 6), "") == "Hello world.")
}

@Test @MainActor func typingInsideBoldTextStaysInsideTheDelimiters() throws {
    // The delimiters are not rendered, so an edit inside the visible word must land
    // between the asterisks rather than outside them.
    let editor = Editor("A **bold** word.")
    let offset = editor.renderOffset(of: "bold") + 2
    #expect(try editor.applying(offset ..< offset, "X") == "A **boXld** word.")
}

@Test @MainActor func typingInsideALinkLabelDoesNotTouchTheURL() throws {
    let editor = Editor("See [the docs](https://example.com) now.")
    let offset = editor.renderOffset(of: "docs")
    #expect(try editor.applying(offset ..< offset, "good ") == "See [the good docs](https://example.com) now.")
}

@Test @MainActor func typingInsideAHeadingKeepsTheHashes() throws {
    let editor = Editor("# Title")
    let offset = editor.renderOffset(of: "Title") + 5
    #expect(try editor.applying(offset ..< offset, "s") == "# Titles")
}

@Test @MainActor func typingInsideACodeFenceEditsTheCode() throws {
    let editor = Editor("```\nlet x = 1\n```")
    let offset = editor.renderOffset(of: "let x")
    let result = try editor.applying(offset ..< offset, "// ")
    #expect(result.contains("// let x = 1"))
    #expect(result.hasPrefix("```"), "the fence must survive")
}

// MARK: Refusals

@Test @MainActor func editingABulletIsRefused() {
    // The bullet is text the renderer invented. It has no source, and mapping it to
    // the nearest run would put the keystroke in the wrong place.
    let editor = Editor("- an item")
    // Offset 0 is the bullet glyph itself.
    #expect(editor.map(0 ..< 1, "X") == .failure(.syntheticText))
}

@Test @MainActor func editingACheckboxIsRefused() {
    let editor = Editor("- [ ] a task")
    #expect(editor.map(0 ..< 1, "X") == .failure(.syntheticText))
}

@Test @MainActor func editingAnOrdinalIsRefused() {
    let editor = Editor("1. first")
    #expect(editor.map(0 ..< 1, "X") == .failure(.syntheticText))
}

@Test @MainActor func typingOverATableIsRefused() {
    // A table is one attachment character. Typing over it would replace the whole
    // table with a letter.
    let editor = Editor("| a | b |\n|---|---|\n| 1 | 2 |")
    #expect(editor.map(0 ..< 1, "X") == .failure(.attachment))
}

@Test @MainActor func typingOverADiagramIsRefused() {
    let editor = Editor("```mermaid\ngraph TD\nA-->B\n```")
    #expect(editor.map(0 ..< 1, "X") == .failure(.attachment))
}

@Test @MainActor func typingOverDisplayMathIsRefused() {
    let editor = Editor("$$\nx^2\n$$")
    #expect(editor.map(0 ..< 1, "X") == .failure(.attachment))
}

@Test @MainActor func anEditSpanningTwoBlocksIsRefused() {
    // Merging two blocks by selecting across them is a real thing to want, but it
    // cannot be mapped as one range, so it is refused rather than guessed.
    let editor = Editor("First paragraph.\n\nSecond paragraph.")
    let start = editor.renderOffset(of: "paragraph.")
    let end = editor.renderOffset(of: "Second") + 6
    #expect(editor.map(start ..< end, "X") == .failure(.crossesBlocks))
}

@Test @MainActor func everyRefusalLeavesTheSourceUntouched() {
    // The contract: a refused edit costs a keystroke, never a document.
    let editor = Editor("- item\n\n| a |\n|---|\n| 1 |")
    let before = editor.source.text
    for range in [0 ..< 1, 2 ..< 3, 5 ..< 6] {
        _ = editor.map(range, "X")
    }
    #expect(editor.source.text == before)
}

// MARK: Multibyte

@Test @MainActor func typingAfterAnEmojiLandsInTheRightPlace() throws {
    // The rendered string counts UTF-16, the source counts UTF-8. An emoji is two
    // units against four bytes, so an offset carried across without conversion
    // lands two bytes early and splits a character.
    let editor = Editor("👋 hello")
    let offset = editor.renderOffset(of: "hello") + 5
    #expect(try editor.applying(offset ..< offset, "!") == "👋 hello!")
}

@Test @MainActor func typingAfterCJKLandsInTheRightPlace() throws {
    let editor = Editor("日本語 text")
    let offset = editor.renderOffset(of: "text") + 4
    #expect(try editor.applying(offset ..< offset, "!") == "日本語 text!")
}

@Test @MainActor func typingBetweenTwoEmojiDoesNotSplitEither() throws {
    let editor = Editor("👋👋")
    // Between them: two UTF-16 units in.
    #expect(try editor.applying(2 ..< 2, "x") == "👋x👋")
}
