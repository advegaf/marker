import Testing
import Foundation
@testable import MarkerCore

// cmark's smart punctuation rewrites the text of a node while reporting a source
// range that still covers the original bytes. Verify-by-slice then compares a
// 3-byte ’ against a 1-byte ' and fails, the block is marked opaque, and a normal
// English paragraph renders as raw Markdown in a monospaced panel.
//
// It shipped that way, and it was invisible in the fixtures because none of them
// contained an apostrophe. It was found by opening this project's own
// ARCHITECTURE.md in the app.
//
// The parser passes `.disableSmartOpts` now. These pin that down from both ends:
// the characters must survive the round trip, and the blocks must not go opaque.

private func blocks(_ markdown: String) -> (MarkdownSource, [BlockNode]) {
    let source = MarkdownSource(markdown)
    return (source, MarkdownParser.parse(source).blocks)
}

private func renderedText(_ markdown: String) -> String {
    let (_, blocks) = blocks(markdown)
    return blocks.flatMap(\.runs).map(\.text).joined()
}

@Test func straightApostrophesSurviveParsing() {
    let text = renderedText("It holds the file's UTF-8 bytes.")
    #expect(text.contains("file's"), "apostrophe was curled: <<<\(text)>>>")
    #expect(!text.contains("\u{2019}"), "a right single quote appeared in <<<\(text)>>>")
}

@Test func straightQuotesSurviveParsing() {
    let text = renderedText(#"She said "no" and meant it."#)
    #expect(text.contains("\"no\""), "quotes were curled: <<<\(text)>>>")
    #expect(!text.contains("\u{201C}") && !text.contains("\u{201D}"),
            "a curly double quote appeared in <<<\(text)>>>")
}

@Test func doubleHyphensDoNotBecomeDashes() {
    // This one matters twice over: the project's writing rule bans em and en
    // dashes outright, so silently drawing one the author did not type would be
    // wrong even if the source map could cope with it.
    let text = renderedText("Pass --force to skip it, and --- ends the argument list.")
    #expect(text.contains("--force"), "a double hyphen was rewritten: <<<\(text)>>>")
    #expect(!text.contains("\u{2013}"), "an en dash appeared in <<<\(text)>>>")
    #expect(!text.contains("\u{2014}"), "an em dash appeared in <<<\(text)>>>")
}

@Test func ellipsesAreNotFolded() {
    let text = renderedText("Wait for it... then press return.")
    #expect(text.contains("..."), "three dots became one glyph: <<<\(text)>>>")
    #expect(!text.contains("\u{2026}"), "an ellipsis character appeared in <<<\(text)>>>")
}

@Test func aParagraphWithAnApostropheIsNotOpaque() {
    // The actual failure mode. An opaque block still renders, which is why this
    // shipped: the page looked wrong rather than crashing, and only in paragraphs
    // that happened to contain punctuation cmark wanted to rewrite.
    let (_, parsed) = blocks("`MarkdownSource` holds the file's UTF-8 bytes.")
    #expect(parsed.count == 1)
    if case .opaque(let raw) = parsed.first?.kind {
        Issue.record("a plain paragraph with an apostrophe went opaque: <<<\(raw)>>>")
    }
}

@Test func everyRunStillMapsBackWhenPunctuationIsPresent() {
    let markdown = """
    A paragraph with the file's name, a "quoted" phrase, an ellipsis... and a
    --flag, wrapped across two lines so the newline folding path runs too.
    """
    let source = MarkdownSource(markdown)
    let result = MarkdownParser.parse(source)
    #expect(result.opaqueBlockCount == 0, "lowering gave up on a block it should have mapped")
    for block in result.blocks {
        for run in block.runs where !run.style.contains(.math) {
            // Synthetic runs (soft and hard breaks) carry an empty anchor range,
            // same exclusion SourceMapTests uses.
            guard !run.sourceRange.isEmpty else { continue }
            #expect(SourceVerifier.produces(run.text, at: run.sourceRange, in: source),
                    "run \(run.sourceRange) does not produce <<<\(run.text)>>>")
        }
    }
}
