import Testing
@testable import MarkerCore

// The byte/line/column conversion is where emoji and CJK documents get silently
// corrupted, so it gets tested before anything is built on top of it.

@Test func lineIndexFindsEveryLineStart() {
    let index = LineIndex("a\nbb\n\nccc")
    #expect(index.lineStarts == [0, 2, 5, 6])
    #expect(index.lineCount == 4)
}

@Test func byteOffsetIsOneBasedInBothAxes() {
    let index = LineIndex("hello\nworld")
    #expect(index.byteOffset(line: 1, column: 1) == 0)
    #expect(index.byteOffset(line: 2, column: 1) == 6)
    #expect(index.byteOffset(line: 2, column: 6) == 11)
}

@Test func byteOffsetRejectsOutOfRangeLocations() {
    let index = LineIndex("hi")
    #expect(index.byteOffset(line: 0, column: 1) == nil)
    #expect(index.byteOffset(line: 9, column: 1) == nil)
    #expect(index.byteOffset(line: 1, column: 0) == nil)
    #expect(index.byteOffset(line: 1, column: 99) == nil)
}

@Test func columnsAreUTF8BytesNotCharacters() {
    // "héllo" is 6 UTF-8 bytes: the é is two. cmark counts bytes, so column 4
    // must land after the é, not after the third Character.
    let index = LineIndex("héllo\nx")
    #expect(index.byteOffset(line: 1, column: 4) == 3)
    #expect(index.byteOffset(line: 2, column: 1) == 7)  // h + é(2) + l + l + o + \n
}

@Test func emojiAndCJKDoNotShiftLaterLines() {
    let source = "👋 hi\n日本語\ntail"
    let index = LineIndex(source)
    // 👋 is 4 bytes, space 1, "hi" 2, newline 1 => line 2 starts at byte 8.
    #expect(index.byteOffset(line: 2, column: 1) == 8)
    // Three CJK glyphs at 3 bytes each plus a newline.
    #expect(index.byteOffset(line: 3, column: 1) == 18)
}

@Test func sliceReturnsExactlyTheRequestedBytes() {
    let source = MarkdownSource("# Title\n\nBody **bold** here.")
    #expect(source.slice(0 ..< 7) == "# Title")
    #expect(source.slice(14 ..< 22) == "**bold**")
    #expect(source.slice(0 ..< 9999) == nil)
}

@Test func applyReturnsAnInverseThatRestoresTheSource() {
    var source = MarkdownSource("one two three")
    let edit = TextEdit(byteRange: 4 ..< 7, replacement: "TWO")
    let inverse = source.apply(edit)
    #expect(source.text == "one TWO three")
    source.apply(inverse)
    #expect(source.text == "one two three")
}

@Test func applySurvivesMultibyteReplacement() {
    var source = MarkdownSource("a b")
    let inverse = source.apply(TextEdit(byteRange: 2 ..< 3, replacement: "日本"))
    #expect(source.text == "a 日本")
    #expect(source.byteCount == 8)
    source.apply(inverse)
    #expect(source.text == "a b")
}

@Test func deltaAndAppliedRangeAgreeWithTheSplice() {
    let edit = TextEdit(byteRange: 5 ..< 10, replacement: "abc")
    #expect(edit.delta == -2)
    #expect(edit.appliedRange == 5 ..< 8)
}
