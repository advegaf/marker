import Testing
import Foundation
@testable import MarkerCore

// The step 1 gate: every run's source range must slice back to that run's own text.
// If this drifts, every edit corrupts the file, so it is checked before a single
// line of editing code exists.

private func parse(_ markdown: String) -> (MarkdownSource, MarkdownParser.Result) {
    let source = MarkdownSource(markdown)
    return (source, MarkdownParser.parse(source))
}

/// Math runs are the one place a run's source range is deliberately wider than its
/// text: the range covers `$…$` including the delimiters, so selecting the formula
/// selects the thing an author would want to edit, while the text is the LaTeX the
/// renderer is handed.
private func assertRunMapsBack(_ run: InlineRun, in source: MarkdownSource, label: String) {
    if run.style.contains(.math) {
        #expect(source.slice(run.sourceRange) == "$\(run.text)$",
                "\(label) math run does not cover its delimiters")
    } else {
        #expect(SourceVerifier.produces(run.text, at: run.sourceRange, in: source),
                "\(label) range \(run.sourceRange) does not produce <<<\(run.text)>>>")
    }
}

/// Asserts the round trip for every run the lowering claims is exact.
private func assertRunsSliceBack(_ markdown: String, file: String = #file, line: Int = #line) {
    let (source, result) = parse(markdown)
    #expect(result.opaqueBlockCount == 0, "lowering gave up on a block it should have mapped")
    for block in result.blocks {
        for run in block.runs {
            // Synthetic runs (soft and hard breaks) carry an empty anchor range.
            guard !run.sourceRange.isEmpty else { continue }
            // Checked through the same verifier the lowering used, recovered runs
            // included. A recovered range is still a correct range.
            assertRunMapsBack(run, in: source, label: "run \(run.id.value)")
        }
        #expect(source.slice(block.sourceRange) != nil,
                "block \(block.id.value) has an out of bounds range")
    }
}

@Test func plainParagraphRunsSliceBack() {
    assertRunsSliceBack("A plain paragraph with no styling at all.")
}

@Test func inlineStylesSliceBack() {
    assertRunsSliceBack("Text with *emphasis*, **strong**, ~~struck~~ and `code` inline.")
}

@Test func linksMapToDisplayTextNotTheURL() {
    let (source, result) = parse("See [the docs](https://example.com/very/long/path) for more.")
    let linkRun = result.blocks[0].runs.first { $0.linkURL != nil }
    #expect(linkRun != nil)
    // The range must cover the display text, not the destination. This is what makes
    // typing at the end of a link land inside the brackets with no special case.
    #expect(source.slice(linkRun!.sourceRange) == "the docs")
    #expect(linkRun!.linkURL == "https://example.com/very/long/path")
}

@Test func headingsCarryTheirLevelAndText() {
    let (_, result) = parse("# One\n\n## Two\n\n###### Six\n")
    let levels = result.blocks.compactMap { block -> Int? in
        if case .heading(let level) = block.kind { return level }
        return nil
    }
    #expect(levels == [1, 2, 6])
}

// The cases cmark is documented to compute against a dedented buffer. These are
// the ones that would silently corrupt saves, so each gets its own test.

@Test func blockQuoteRunsSliceBack() {
    assertRunsSliceBack("""
    > Quoted text with **strong** inside it.
    >
    > A second quoted paragraph.
    """)
}

@Test func nestedListContinuationRunsSliceBack() {
    assertRunsSliceBack("""
    - First item
    - Second item that wraps onto
      a continuation line with *emphasis*
      - Nested item with `code`
        - Deeper still
    - Third item
    """)
}

@Test func mixedIndentationRunsSliceBack() {
    assertRunsSliceBack("""
    1. Ordered item

       An indented paragraph inside the item, with a [link](https://example.com).

    2. Second item
       > A quote inside a list item with **strong** text.
    """)
}

@Test func emojiAndCJKRunsSliceBack() {
    assertRunsSliceBack("""
    A paragraph with 👋 emoji, 日本語 text, and **強調** mixed in.

    - 👨‍👩‍👧‍👦 a family emoji in a list with *emphasis*
    - naïve café résumé
    """)
}

@Test func codeFencesKeepTheirLanguageAndBody() {
    let (_, result) = parse("""
    ```swift
    let x = 1
    ```

    ```
    no language
    ```
    """)
    guard case .codeFence(let language, let code) = result.blocks[0].kind else {
        Issue.record("expected a code fence"); return
    }
    #expect(language == "swift")
    #expect(code == "let x = 1")
    guard case .codeFence(let noLanguage, _) = result.blocks[1].kind else {
        Issue.record("expected a second code fence"); return
    }
    #expect(noLanguage == nil)
}

@Test func mermaidFencesBecomeDiagramBlocks() {
    let (_, result) = parse("""
    ```mermaid
    graph TD
        A --> B
    ```
    """)
    guard case .mermaid(let diagram) = result.blocks[0].kind else {
        Issue.record("expected a mermaid block"); return
    }
    #expect(diagram == "graph TD\n    A --> B")
}

@Test func tablesLowerToColumnsRowsAndAlignment() {
    let (_, result) = parse("""
    | Feature | Free | Pro |
    |:--------|:----:|----:|
    | Render  | yes  | yes |
    | Edit    | no   | yes |
    """)
    guard case .table(let model) = result.blocks[0].kind else {
        Issue.record("expected a table"); return
    }
    #expect(model.columns.map(\.header) == ["Feature", "Free", "Pro"])
    #expect(model.columns.map(\.alignment) == [.left, .center, .right])
    #expect(model.rows == [["Render", "yes", "yes"], ["Edit", "no", "yes"]])
}

@Test func listContextRecordsDepthOrdinalAndCheckbox() {
    let (_, result) = parse("""
    - [ ] unchecked
    - [x] checked

    1. first
    2. second
    """)
    #expect(result.blocks[0].context.checked == false)
    #expect(result.blocks[1].context.checked == true)
    #expect(result.blocks[0].context.listDepth == 1)
    #expect(result.blocks[2].context.ordinal == 1)
    #expect(result.blocks[3].context.ordinal == 2)
}

/// The whole corpus at once, plus a report of how often cmark's inline columns
/// actually drift. The numbers are asserted so a regression in the recovery path
/// shows up as a test failure rather than as silent corruption.
@Test func kitchenSinkFixtureMapsCleanly() throws {
    let fixture = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // MarkerCoreTests
        .deletingLastPathComponent()   // Tests
        .deletingLastPathComponent()   // MarkerKit
        .deletingLastPathComponent()   // Packages
        .deletingLastPathComponent()   // repo root
        .appendingPathComponent("QA/fixtures/kitchen-sink.md")
    let markdown = try String(contentsOf: fixture, encoding: .utf8)
    let source = MarkdownSource(markdown)
    let result = MarkdownParser.parse(source)

    #expect(!result.blocks.isEmpty)
    for block in result.blocks {
        for run in block.runs where !run.sourceRange.isEmpty {
            assertRunMapsBack(run, in: source, label: "block \(block.id.value) run \(run.id.value)")
        }
    }
    // No block in the corpus should be untrustworthy. If this ever fails, the
    // recovery path stopped working, not the fixture.
    #expect(result.opaqueBlockCount == 0)
    // Two runs legitimately need correcting: swift-markdown reports inline-code
    // ranges off by one on both bounds when the code spans a line break. Asserted
    // rather than tolerated, so the number moving is a visible event.
    #expect(result.recoveredRunCount == 2)
    print("[source map] recovered runs: \(result.recoveredRunCount), opaque blocks: \(result.opaqueBlockCount)")
}
