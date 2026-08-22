import Testing
import AppKit
import MarkerCore
@testable import MarkerRender

// The step 2a gate. TextKit 2 lays out lazily around the viewport, so a text view
// that has not been told to lay out the whole document reports a short frame, the
// scroll view inherits that height, and scrolling stops before the end of the file.
// A visual check will not catch a regression here, because it only shows on
// documents longer than a screen.

private func longMarkdown(sections: Int) -> MarkdownSource {
    var lines = ["# Long"]
    for index in 1 ... sections {
        lines.append("")
        lines.append("## Section \(index)")
        lines.append("")
        lines.append(String(repeating: "body text that has to wrap at least once ", count: 3))
    }
    lines.append("")
    lines.append("END")
    return MarkdownSource(lines.joined(separator: "\n"))
}

@Test @MainActor func frameCoversTheWholeLaidOutDocument() {
    let theme = MarkerTheme.standard(.light)
    let view = MarkdownTextView(theme: theme)
    let rendered = DocumentRenderer(theme: theme, mode: .image).render(longMarkdown(sections: 200))
    view.setContent(rendered, theme: theme, availableWidth: 900)

    let layoutManager = view.textLayoutManager!
    let used = layoutManager.usageBoundsForTextContainer
    #expect(view.frame.height >= used.maxY + theme.metrics.pageInset * 2,
            "frame \(view.frame.height) is shorter than the laid out content \(used.maxY)")
}

@Test @MainActor func aLongDocumentIsTallerThanAShortOne() {
    // Guards against the failure mode where the frame is "tall enough" only because
    // some constant made it large regardless of content.
    let theme = MarkerTheme.standard(.light)
    let renderer = DocumentRenderer(theme: theme, mode: .image)

    let short = MarkdownTextView(theme: theme)
    short.setContent(renderer.render(longMarkdown(sections: 2)), theme: theme, availableWidth: 900)

    let long = MarkdownTextView(theme: theme)
    long.setContent(renderer.render(longMarkdown(sections: 200)), theme: theme, availableWidth: 900)

    #expect(long.frame.height > short.frame.height * 10)
}

@Test @MainActor func theLastBlockIsLaidOutNotJustTheFirstScreenful() {
    let theme = MarkerTheme.standard(.light)
    let view = MarkdownTextView(theme: theme)
    let source = longMarkdown(sections: 200)
    view.setContent(DocumentRenderer(theme: theme, mode: .image).render(source), theme: theme, availableWidth: 900)

    // Ask the layout manager for the fragment holding the final character. If only
    // the viewport was laid out, this is nil and the document view is short.
    // Probe one position back from documentRange.endLocation, which is exclusive and
    // so is not inside any fragment by definition.
    let layoutManager = view.textLayoutManager!
    let end = layoutManager.documentRange.endLocation
    let lastCharacter = layoutManager.location(end, offsetBy: -1) ?? end
    let fragment = layoutManager.textLayoutFragment(for: lastCharacter)
    #expect(fragment != nil, "the end of the document was never laid out")

    // And that fragment must sit at the bottom of the frame, not near the top.
    if let fragment {
        #expect(fragment.layoutFragmentFrame.maxY > view.frame.height * 0.5,
                "the last fragment is not near the end of the document view")
    }
}

@Test @MainActor func measureIsCappedAndCentredAtEveryWidth() {
    let theme = MarkerTheme.standard(.light)
    let view = MarkdownTextView(theme: theme)
    let rendered = DocumentRenderer(theme: theme, mode: .image).render(MarkdownSource("# Title\n\nBody."))

    for width in [420.0, 900.0, 2400.0] as [CGFloat] {
        view.setContent(rendered, theme: theme, availableWidth: width)
        let measure = view.textContainer!.size.width
        #expect(measure <= theme.metrics.contentWidth + 1, "measure ran past the readable cap at \(width)")
        #expect(view.measuredWidth == width)
        // Centred: the two insets plus the column account for the whole width.
        let inset = view.textContainerInset.width
        #expect(abs((inset * 2 + measure) - max(width, measure + inset * 2)) < 1.5)
    }
}
