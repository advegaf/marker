import Testing
import Foundation
import MarkerCore
@testable import MarkerRender

// The step 2 gate: the source and render coordinate spaces must be exact inverses
// for every run. If they are not, the caret lands in the wrong place and an edit
// splices the wrong bytes.

private func build(_ markdown: String) -> (MarkdownSource, BlockIndex, NSAttributedString) {
    let source = MarkdownSource(markdown)
    let rendered = DocumentRenderer(theme: .standard(.light), mode: .image).renderDocument(source)
    return (source, rendered.index, rendered.attributed)
}

/// Walks every run and checks the round trip in both directions.
private func assertRoundTrip(_ markdown: String) {
    let (_, index, _) = build(markdown)
    for (position, block) in index.blocks.enumerated() {
        let entry = index.entries[position]
        for (runPosition, run) in block.runs.enumerated() where !run.sourceRange.isEmpty {
            let renderStart = entry.runStarts[runPosition]

            let backToSource = index.sourceOffset(forRender: renderStart)
            #expect(backToSource == run.sourceRange.lowerBound,
                    "render \(renderStart) mapped to \(backToSource ?? -1), expected \(run.sourceRange.lowerBound)")

            let backToRender = index.renderOffset(forSource: run.sourceRange.lowerBound)
            #expect(backToRender == renderStart,
                    "source \(run.sourceRange.lowerBound) mapped to \(backToRender ?? -1), expected \(renderStart)")
        }
    }
}

@Test func roundTripsPlainProse() {
    assertRoundTrip("A first paragraph.\n\nA second one, longer than the first.")
}

@Test func roundTripsInlineStyles() {
    assertRoundTrip("Text with *emphasis*, **strong**, `code` and a [link](https://example.com).")
}

@Test func roundTripsHeadingsAndLists() {
    assertRoundTrip("""
    # Title

    - one
    - two with **strong**
      - nested

    1. first
    2. second
    """)
}

@Test func roundTripsQuotesAndMultibyte() {
    assertRoundTrip("""
    > Quoted with 日本語 and 👋 in it.

    A paragraph with café and naïve.
    """)
}

@Test func listMarkerOffsetsDoNotShiftTheFirstRun() {
    // The bullet is rendered text that has no source of its own. If it were counted
    // as part of the first run, every caret in every list would be off by three.
    let (_, index, attributed) = build("- item text")
    let entry = index.entries[0]
    let run = index.blocks[0].runs[0]
    let rendered = attributed.string as NSString
    let slice = rendered.substring(with: NSRange(location: entry.runStarts[0], length: run.renderLength))
    #expect(slice == "item text")
    #expect(entry.runStarts[0] > entry.renderStart, "the bullet should occupy render offsets before the run")
}

@Test func blockLookupFindsTheRightBlockAtEveryOffset() {
    let (_, index, attributed) = build("# One\n\nTwo\n\n- Three")
    for offset in 0 ..< attributed.length {
        guard let position = index.blockIndex(forRender: offset) else {
            Issue.record("offset \(offset) mapped to no block"); continue
        }
        let entry = index.entries[position]
        #expect(offset >= entry.renderStart)
    }
}

@Test func offsetsPastTheLastRunClampIntoTheBlock() {
    let (source, index, _) = build("A paragraph.")
    let end = index.entries[0].renderRange.upperBound
    let mapped = index.sourceOffset(forRender: end)
    #expect(mapped != nil)
    #expect(mapped! <= source.byteCount)
}
