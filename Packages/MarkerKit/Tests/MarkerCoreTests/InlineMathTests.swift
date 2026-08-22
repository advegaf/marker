import Testing
@testable import MarkerCore

// The delimiter rules exist because `$` is also a currency sign and a shell
// variable marker. Getting them wrong turns prose into a formula, which is far
// more visible than failing to find a formula that was there.

private func segments(_ text: String) -> [InlineMathSplitter.Segment] {
    InlineMathSplitter.split(text)
}

private func texts(_ text: String) -> [String] { segments(text).map(\.text) }
private func hasMath(_ text: String) -> Bool { segments(text).contains(where: \.isMath) }
private func mathTexts(_ text: String) -> [String] { segments(text).filter(\.isMath).map(\.text) }

/// Every segment's byte offset and length must add back up to the input.
private func assertCoversInput(_ text: String) {
    let parts = InlineMathSplitter.split(text)
    var expected = 0
    for part in parts {
        #expect(part.byteOffset == expected, "gap or overlap before <<<\(part.text)>>> in <<<\(text)>>>")
        expected += part.byteLength
    }
    #expect(expected == text.utf8.count, "segments do not span <<<\(text)>>>")
}

@Test func findsASimpleFormula() {
    #expect(texts("a $x+1$ b") == ["a ", "x+1", " b"])
    #expect(segments("a $x+1$ b").map(\.isMath) == [false, true, false])
}

@Test func textWithoutDollarsIsOneSegment() {
    #expect(texts("no math here") == ["no math here"])
    #expect(hasMath("no math here") == false)
}

@Test func pricesAreNotFormulas() {
    // The naive rule turns "$5 and $" into a formula and eats the sentence.
    #expect(hasMath("it costs $5 and $10 total") == false)
    #expect(hasMath("$5") == false)
    #expect(hasMath("worth $1,000 or $2,000") == false)
}

@Test func anOpeningDelimiterMustHugItsContent() {
    // "$ x $" is prose containing dollar signs, not a formula.
    #expect(hasMath("a $ x $ b") == false)
}

@Test func aClosingDelimiterMustHugItsContent() {
    #expect(hasMath("a $x $ b") == false)
}

@Test func escapedDelimitersAreLiteral() {
    // \$ is a dollar sign the author escaped, not a delimiter.
    #expect(hasMath("\\$not math\\$") == false)
    #expect(hasMath("cost \\$5 to \\$9") == false)
}

@Test func anEscapedBackslashStillOpensAFormula() {
    // \\$ is an escaped backslash followed by a real delimiter, so counting the
    // run matters rather than just looking at the previous character.
    #expect(mathTexts("a \\\\$x$ b") == ["x"])
}

@Test func aFormulaDoesNotSpanALineBreak() {
    // A stray delimiter must not swallow the rest of the paragraph.
    #expect(hasMath("open $here\nand $ there") == false)
}

@Test func anUnclosedDelimiterLeavesTextAlone() {
    #expect(texts("half open $x + 1") == ["half open $x + 1"])
}

@Test func emptyFormulaIsNotAFormula() {
    #expect(hasMath("a $$ b") == false)
}

@Test func backslashHeavyLatexSurvives() {
    // Working on raw source rather than cmark's unescaped text is the whole reason
    // this type exists: `x\_1` would otherwise arrive as `x_1`.
    #expect(mathTexts("see $\\frac{a}{b}$ and $x\\_1$") == ["\\frac{a}{b}", "x\\_1"])
}

@Test func twoFormulasInOneLine() {
    #expect(texts("$a$ and $b$") == ["a", " and ", "b"])
}

@Test func segmentsAlwaysSpanTheInput() {
    for sample in [
        "a $x+1$ b",
        "no math",
        "it costs $5 and $10",
        "\\$literal\\$",
        "$a$ and $b$ and trailing",
        "日本語 $x$ と 👋 $y$",
        "$",
        "",
    ] {
        assertCoversInput(sample)
    }
}

@Test func multibyteTextKeepsByteOffsetsHonest() {
    // Offsets are UTF-8 bytes, and the caller turns them into source ranges, so an
    // emoji miscounted here corrupts an edit later.
    let parts = InlineMathSplitter.split("👋 $x$")
    let math = parts.first { $0.isMath }
    #expect(math?.byteOffset == 5, "emoji is 4 bytes plus a space")
    #expect(math?.byteLength == 3, "the segment covers $x$ including delimiters")
}
