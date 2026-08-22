import Testing
@testable import MarkerCore

// A toggle has two halves and the second one is where the bugs are: removing a
// style has to find the delimiters that produced it, which are not always the ones
// this code would have written.

/// Applies a toggle and returns the resulting source plus what the selection became.
private func toggle(
    _ style: InlineFormat.Style, over range: Range<Int>, in markdown: String
) throws -> (text: String, selection: Range<Int>, removed: Bool) {
    var source = MarkdownSource(markdown)
    let blocks = MarkdownParser.parse(source).blocks
    let result = try InlineFormat.toggle(style, over: range, in: source, blocks: blocks).get()
    for edit in result.edits { source.apply(edit) }
    return (source.text, result.selection, result.didRemove)
}

/// Byte range of `needle` in `haystack`.
private func range(of needle: String, in haystack: String) -> Range<Int> {
    let found = haystack.range(of: needle)!
    let start = haystack[haystack.startIndex ..< found.lowerBound].utf8.count
    return start ..< (start + needle.utf8.count)
}

@Test func addingBoldWrapsTheSelection() throws {
    let text = "make this bold"
    #expect(try toggle(.strong, over: range(of: "this", in: text), in: text).text == "make **this** bold")
}

@Test func addingItalicAndStrikethrough() throws {
    let text = "one two three"
    #expect(try toggle(.emphasis, over: range(of: "two", in: text), in: text).text == "one _two_ three")
    #expect(try toggle(.strikethrough, over: range(of: "two", in: text), in: text).text == "one ~~two~~ three")
}

@Test func removingBoldTakesTheDelimitersOff() throws {
    let text = "make **this** bold"
    let result = try toggle(.strong, over: range(of: "this", in: text), in: text)
    #expect(result.text == "make this bold")
    #expect(result.removed)
}

@Test func removingItalicWrittenWithAsterisksWorks() throws {
    // The delimiters are read off the source, not assumed, because italic can be
    // written either way and removing the wrong pair breaks the document.
    let text = "one *two* three"
    #expect(try toggle(.emphasis, over: range(of: "two", in: text), in: text).text == "one two three")
}

@Test func removingItalicWrittenWithUnderscoresWorks() throws {
    let text = "one _two_ three"
    #expect(try toggle(.emphasis, over: range(of: "two", in: text), in: text).text == "one two three")
}

@Test func togglingTwiceReturnsTheOriginal() throws {
    // The property that makes it a toggle rather than two commands.
    for style in InlineFormat.Style.allCases {
        let text = "round trip me"
        let once = try toggle(style, over: range(of: "trip", in: text), in: text)
        var source = MarkdownSource(once.text)
        let blocks = MarkdownParser.parse(source).blocks
        let twice = try InlineFormat.toggle(style, over: once.selection, in: source, blocks: blocks).get()
        for edit in twice.edits { source.apply(edit) }
        #expect(source.text == text, "\(style) did not round trip: got <<<\(source.text)>>>")
    }
}

@Test func theSelectionFollowsTheText() throws {
    // After wrapping, the same words must still be selected, or typing replaces the
    // delimiters that were just added.
    let text = "make this bold"
    let result = try toggle(.strong, over: range(of: "this", in: text), in: text)
    let selected = String(
        decoding: Array(result.text.utf8)[result.selection], as: UTF8.self
    )
    #expect(selected == "this")
}

@Test func selectingSomethingAlreadyCodeRemovesTheCode() throws {
    // A toggle, so a selection that is already a code span comes back plain.
    let text = "call `foo` now"
    let result = try toggle(.code, over: range(of: "foo", in: text), in: text)
    #expect(result.text == "call foo now")
    #expect(result.removed)
}

@Test func contentContainingBackticksGetsALongerFence() throws {
    // CommonMark: content with a run of n backticks needs at least n+1 to fence it,
    // padded so the fence is not absorbed into the content. The selection here is
    // not itself a code span, it merely contains one, so this is a wrap.
    let text = "run a `b` c now"
    let result = try toggle(.code, over: range(of: "a `b` c", in: text), in: text)
    #expect(result.text == "run `` a `b` c `` now", "got <<<\(result.text)>>>")
}

@Test func plainInlineCodeUsesOneBacktick() throws {
    let text = "call foo now"
    #expect(try toggle(.code, over: range(of: "foo", in: text), in: text).text == "call `foo` now")
}

@Test func formattingInsideAHeadingWorks() throws {
    let text = "# A title here"
    #expect(try toggle(.strong, over: range(of: "title", in: text), in: text).text == "# A **title** here")
}

// MARK: Refusals

@Test func anEmptySelectionIsRefused() {
    let source = MarkdownSource("nothing selected")
    let blocks = MarkdownParser.parse(source).blocks
    #expect(InlineFormat.toggle(.strong, over: 3 ..< 3, in: source, blocks: blocks) == .failure(.emptySelection))
}

@Test func aSelectionSpanningTwoBlocksIsRefused() {
    let text = "First para.\n\nSecond para."
    let source = MarkdownSource(text)
    let blocks = MarkdownParser.parse(source).blocks
    let span = range(of: "para.", in: text).lowerBound ..< range(of: "Second", in: text).upperBound
    #expect(InlineFormat.toggle(.strong, over: span, in: source, blocks: blocks) == .failure(.crossesBlocks))
}

@Test func formattingACodeFenceIsRefused() {
    // Bold inside a code block would be shown literally, so offering it is a lie.
    let text = "```\nlet x = 1\n```"
    let source = MarkdownSource(text)
    let blocks = MarkdownParser.parse(source).blocks
    #expect(InlineFormat.toggle(.strong, over: range(of: "let", in: text), in: source, blocks: blocks)
            == .failure(.notFormattable))
}

@Test func formattingATableIsRefused() {
    let text = "| a | b |\n|---|---|\n| 1 | 2 |"
    let source = MarkdownSource(text)
    let blocks = MarkdownParser.parse(source).blocks
    #expect(InlineFormat.toggle(.strong, over: 2 ..< 3, in: source, blocks: blocks)
            == .failure(.notFormattable))
}

// MARK: State

@Test func activeStateReflectsWhatIsThere() {
    let text = "a **bold** and _italic_ line"
    let source = MarkdownSource(text)
    let blocks = MarkdownParser.parse(source).blocks

    #expect(InlineFormat.isActive(.strong, over: range(of: "bold", in: text), blocks: blocks))
    #expect(InlineFormat.isActive(.emphasis, over: range(of: "italic", in: text), blocks: blocks))
    #expect(!InlineFormat.isActive(.strong, over: range(of: "italic", in: text), blocks: blocks))
    #expect(!InlineFormat.isActive(.strong, over: range(of: "line", in: text), blocks: blocks))
}

@Test func aPartlyBoldSelectionIsNotActive() {
    // Half in, half out, so the toggle should add rather than remove.
    let text = "**bold** plain"
    let source = MarkdownSource(text)
    let blocks = MarkdownParser.parse(source).blocks
    let span = range(of: "bold", in: text).lowerBound ..< range(of: "plain", in: text).upperBound
    #expect(!InlineFormat.isActive(.strong, over: span, blocks: blocks))
}

@Test func multibyteSelectionsKeepTheirBounds() throws {
    let text = "say 日本語 loudly"
    let result = try toggle(.strong, over: range(of: "日本語", in: text), in: text)
    #expect(result.text == "say **日本語** loudly")
    let selected = String(decoding: Array(result.text.utf8)[result.selection], as: UTF8.self)
    #expect(selected == "日本語")
}
