import Testing
import AppKit
@testable import MarkerCore
@testable import MarkerRender

// A two column table holding a short identifier next to a paragraph used to give
// the identifier a proportional share of a width it never asked for, so
// `MarkerRender` came out wrapped as "Marker" over "Render" while the paragraph
// column still had room. Shrinking every column by the same factor is wrong when
// the columns are lopsided.
//
// Found by opening this project's own ARCHITECTURE.md in the app.

private func layout(_ markdown: String, width: CGFloat) -> TableLayout.Metrics? {
    let source = MarkdownSource(markdown)
    let blocks = MarkdownParser.parse(source).blocks
    for block in blocks {
        if case .table(let model) = block.kind {
            return TableLayout(model: model, theme: .standard(.light), maxWidth: width).measure()
        }
    }
    return nil
}

private let lopsided = """
| Target | Contents |
|---|---|
| `MarkerCore` | No AppKit. Document model, parser bridge and lowering, the fourteen language highlighter, JSON printer, table model and Markdown writer, and the whole Mermaid engine. |
| `MarkerRender` | AppKit, default MainActor isolation. MarkerTheme, the attributed builder, math and Mermaid drawing, TableLayout, MarkdownTextView, ZoomController. |
"""

@Test @MainActor func aNarrowColumnIsNotSqueezedByItsNeighbour() throws {
    // Column one holds single tokens with no spaces in them, so the width it wants
    // and the width it can survive on are the same number. Squeezing the table
    // must therefore not change it at all: whatever has to give, gives in the
    // paragraph column. Asserting it this way rather than against a hardcoded
    // point size keeps the test honest if the theme's fonts change.
    let roomy = try #require(layout(lopsided, width: 1600))
    let tight = try #require(layout(lopsided, width: 760))

    #expect(tight.columnWidths.count == 2)
    #expect(abs(tight.columnWidths[0] - roomy.columnWidths[0]) < 0.5,
            "column one went from \(roomy.columnWidths[0])pt to \(tight.columnWidths[0])pt when the table was narrowed")
    #expect(tight.columnWidths[1] < roomy.columnWidths[1],
            "the paragraph column should be the one that gives")
}

@Test @MainActor func theTableStillFitsTheAvailableWidth() throws {
    let metrics = try #require(layout(lopsided, width: 760))
    #expect(metrics.size.width <= 760 + 1, "the table is \(metrics.size.width)pt wide in a 760pt column")
}

@Test @MainActor func aTableThatFitsIsNotShrunkAtAll() throws {
    let narrow = """
    | A | B |
    |---|---|
    | one | two |
    """
    let metrics = try #require(layout(narrow, width: 760))
    #expect(metrics.size.width < 760, "a tiny table was stretched to the full column")
}

@Test @MainActor func wordsWiderThanTheWholeColumnStillProduceALayout() throws {
    // When even the words alone do not fit there is nothing to honour, but the
    // table still has to come back with usable numbers rather than zero or NaN.
    let cramped = """
    | Identifier | Identifier |
    |---|---|
    | Supercalifragilisticexpialidocious | Antidisestablishmentarianism |
    """
    let metrics = try #require(layout(cramped, width: 120))
    #expect(metrics.size.width <= 121)
    #expect(metrics.columnWidths.allSatisfy { $0 > 0 && $0.isFinite })
}
