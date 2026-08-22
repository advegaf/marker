import Foundation
import Markdown

/// Walks the cmark AST and produces a flat list of blocks with byte-accurate
/// source ranges.
///
/// Flat rather than nested because the renderer emits one paragraph style per
/// block and the editor maps a caret to exactly one block. Nesting is carried on
/// `BlockContext` instead of in the tree shape.
struct ASTLowering: MarkupWalker {

    let source: MarkdownSource

    private(set) var blocks: [BlockNode] = []
    private(set) var recoveredRunCount = 0
    private(set) var opaqueBlockCount = 0

    private var nextBlockID = 0
    private var nextRunID = 0
    private var listDepth = 0
    private var quoteDepth = 0
    private var pendingOrdinal: Int?
    private var pendingChecked: Bool?
    private var pendingListItemStart = false

    init(source: MarkdownSource) {
        self.source = source
    }

    // MARK: Block visitors

    mutating func visitParagraph(_ paragraph: Paragraph) {
        let range = byteRange(of: paragraph)
        if let latex = Self.displayMathBody(source.slice(range)) {
            append(kind: .displayMath(latex: latex), range: range, runs: [])
            return
        }
        appendInlineBlock(kind: .paragraph, markup: paragraph)
    }

    /// The LaTeX between a paragraph's `$$` fences, or nil if it is not one.
    private static func displayMathBody(_ raw: String?) -> String? {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              trimmed.hasPrefix("$$"), trimmed.hasSuffix("$$"), trimmed.count > 4
        else { return nil }
        return String(trimmed.dropFirst(2).dropLast(2))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    mutating func visitHeading(_ heading: Heading) {
        appendInlineBlock(kind: .heading(level: heading.level), markup: heading)
    }

    mutating func visitCodeBlock(_ codeBlock: CodeBlock) {
        let language = codeBlock.language?.trimmingCharacters(in: .whitespaces)
        // Trailing newline is a fence artefact, not content.
        let code = String(codeBlock.code.dropLast(codeBlock.code.hasSuffix("\n") ? 1 : 0))
        let kind: BlockKind = (language?.lowercased() == "mermaid")
            ? .mermaid(source: code)
            : .codeFence(language: language?.isEmpty == true ? nil : language, code: code)
        append(kind: kind, range: byteRange(of: codeBlock), runs: [])
    }

    mutating func visitThematicBreak(_ thematicBreak: ThematicBreak) {
        append(kind: .thematicBreak, range: byteRange(of: thematicBreak), runs: [])
    }

    mutating func visitHTMLBlock(_ html: HTMLBlock) {
        append(kind: .html(html.rawHTML), range: byteRange(of: html), runs: [])
    }

    mutating func visitBlockQuote(_ blockQuote: BlockQuote) {
        quoteDepth += 1
        descendInto(blockQuote)
        quoteDepth -= 1
    }

    mutating func visitUnorderedList(_ list: UnorderedList) {
        listDepth += 1
        for item in list.listItems {
            pendingChecked = item.checkbox.map { $0 == .checked }
            pendingOrdinal = nil
            pendingListItemStart = true
            descendInto(item)
        }
        listDepth -= 1
    }

    mutating func visitOrderedList(_ list: OrderedList) {
        listDepth += 1
        var ordinal = Int(list.startIndex)
        for item in list.listItems {
            pendingChecked = item.checkbox.map { $0 == .checked }
            pendingOrdinal = ordinal
            pendingListItemStart = true
            descendInto(item)
            ordinal += 1
        }
        listDepth -= 1
    }

    mutating func visitTable(_ table: Markdown.Table) {
        let alignments = table.columnAlignments.map { alignment -> TableModel.Alignment in
            switch alignment {
            case .left: return .left
            case .center: return .center
            case .right: return .right
            case .none: return .none
            @unknown default: return .none
            }
        }
        let headers = Array(table.head.cells).map { plainText(of: $0) }
        let columns = headers.enumerated().map { index, header in
            TableModel.Column(
                header: header,
                alignment: index < alignments.count ? alignments[index] : .none
            )
        }
        let rows = Array(table.body.rows).map { row in Array(row.cells).map { plainText(of: $0) } }
        append(
            kind: .table(TableModel(columns: columns, rows: rows)),
            range: byteRange(of: table),
            runs: []
        )
    }

    // MARK: Block assembly

    private mutating func appendInlineBlock(kind: BlockKind, markup: some Markup) {
        let range = byteRange(of: markup)
        var runs: [InlineRun] = []
        var untrusted = false
        collectRuns(in: markup, style: [], linkURL: nil, into: &runs, untrusted: &untrusted)

        if untrusted {
            opaqueBlockCount += 1
            // Still renders, but as its own source text, so an edit cannot corrupt it.
            append(kind: .opaque(source.slice(range) ?? ""), range: range, runs: [])
            return
        }
        append(kind: kind, range: range, runs: runs)
    }

    private mutating func append(kind: BlockKind, range: Range<Int>, runs: [InlineRun]) {
        blocks.append(BlockNode(
            id: BlockID(nextBlockID),
            kind: kind,
            sourceRange: range,
            context: BlockContext(
                listDepth: listDepth,
                quoteDepth: quoteDepth,
                ordinal: pendingOrdinal,
                checked: pendingChecked,
                isListItemStart: pendingListItemStart
            ),
            runs: runs
        ))
        nextBlockID += 1
        // List-item metadata applies to the first block of the item only.
        pendingListItemStart = false
        pendingOrdinal = nil
        pendingChecked = nil
    }

    // MARK: Inline collection

    private mutating func collectRuns(
        in markup: some Markup,
        style: InlineStyle,
        linkURL: String?,
        into runs: inout [InlineRun],
        untrusted: inout Bool
    ) {
        for child in markup.children {
            switch child {
            case let text as Markdown.Text:
                appendRun(literal: text.string, markup: text, style: style, linkURL: linkURL,
                          into: &runs, untrusted: &untrusted)
            case let code as InlineCode:
                appendRun(literal: code.code, markup: code, style: style.union(.code),
                          linkURL: linkURL, into: &runs, untrusted: &untrusted)
            case let emphasis as Emphasis:
                collectRuns(in: emphasis, style: style.union(.emphasis), linkURL: linkURL,
                            into: &runs, untrusted: &untrusted)
            case let strong as Strong:
                collectRuns(in: strong, style: style.union(.strong), linkURL: linkURL,
                            into: &runs, untrusted: &untrusted)
            case let strike as Strikethrough:
                collectRuns(in: strike, style: style.union(.strikethrough), linkURL: linkURL,
                            into: &runs, untrusted: &untrusted)
            case let link as Markdown.Link:
                collectRuns(in: link, style: style, linkURL: link.destination,
                            into: &runs, untrusted: &untrusted)
            case is SoftBreak:
                appendSynthetic(" ", after: runs.last, style: style, linkURL: linkURL, into: &runs)
            case is LineBreak:
                appendSynthetic("\n", after: runs.last, style: style, linkURL: linkURL, into: &runs)
            case let html as InlineHTML:
                appendRun(literal: html.rawHTML, markup: html, style: style, linkURL: linkURL,
                          into: &runs, untrusted: &untrusted)
            default:
                collectRuns(in: child, style: style, linkURL: linkURL,
                            into: &runs, untrusted: &untrusted)
            }
        }
    }

    /// Verify-by-slice. The mitigation for cmark's inline column drift: never trust
    /// a computed range, always check it against what the node says its text is.
    private mutating func appendRun(
        literal: String,
        markup: some Markup,
        style: InlineStyle,
        linkURL: String?,
        into runs: inout [InlineRun],
        untrusted: inout Bool
    ) {
        guard !literal.isEmpty else { return }
        let computed = byteRange(of: markup)
        var confidence = MapConfidence.exact
        var range = computed

        if !SourceVerifier.produces(literal, at: computed, in: source) {
            // Nudge first, then fall back to searching a window for the literal.
            guard let corrected = SourceVerifier.correctedRange(for: literal, near: computed, in: source)
                    ?? search(for: literal, near: computed) else {
                if ProcessInfo.processInfo.environment["MARKER_MAP_DEBUG"] != nil {
                    print("[map-fail] literal=<<<\(literal)>>> computed=\(computed) slice=<<<\(source.slice(computed) ?? "nil")>>>")
                }
                untrusted = true
                return
            }
            range = corrected
            confidence = .recovered
            recoveredRunCount += 1
        }

        // Inline math is split out of plain text only. Splitting inside inline code
        // would turn `$PATH` in a shell snippet into a formula.
        if !style.contains(.code), let raw = source.slice(range), raw.contains("$") {
            let segments = InlineMathSplitter.split(raw)
            if segments.contains(where: \.isMath) {
                for segment in segments {
                    let start = range.lowerBound + segment.byteOffset
                    appendSegment(
                        segment,
                        sourceRange: start ..< (start + segment.byteLength),
                        style: style,
                        linkURL: linkURL,
                        confidence: confidence,
                        into: &runs
                    )
                }
                return
            }
        }

        runs.append(InlineRun(
            id: RunID(nextRunID),
            sourceRange: range,
            text: literal,
            style: style,
            linkURL: linkURL,
            confidence: confidence
        ))
        nextRunID += 1
    }

    private mutating func appendSegment(
        _ segment: InlineMathSplitter.Segment,
        sourceRange: Range<Int>,
        style: InlineStyle,
        linkURL: String?,
        confidence: MapConfidence,
        into runs: inout [InlineRun]
    ) {
        // Non-math text came off the raw source, so it still carries backslash
        // escapes that cmark would have resolved. Resolve them the same way, or an
        // escaped asterisk would render as a backslash.
        let text = segment.isMath ? segment.text : SourceVerifier.unescaped(segment.text)
        guard !text.isEmpty else { return }
        runs.append(InlineRun(
            id: RunID(nextRunID),
            sourceRange: sourceRange,
            text: text,
            style: segment.isMath ? style.union(.math) : style,
            linkURL: linkURL,
            confidence: confidence
        ))
        nextRunID += 1
    }

    /// A soft or hard break emits visible whitespace that occupies no source of its
    /// own worth mapping, so it is anchored to the end of the previous run.
    private mutating func appendSynthetic(
        _ text: String,
        after previous: InlineRun?,
        style: InlineStyle,
        linkURL: String?,
        into runs: inout [InlineRun]
    ) {
        let anchor = previous?.sourceRange.upperBound ?? 0
        runs.append(InlineRun(
            id: RunID(nextRunID),
            sourceRange: anchor ..< anchor,
            text: text,
            style: style,
            linkURL: linkURL
        ))
        nextRunID += 1
    }

    // MARK: Ranges

    private func byteRange(of markup: some Markup) -> Range<Int> {
        guard let range = markup.range,
              let lower = source.lineIndex.byteOffset(line: range.lowerBound.line,
                                                      column: range.lowerBound.column),
              let upper = source.lineIndex.byteOffset(line: range.upperBound.line,
                                                      column: range.upperBound.column),
              lower <= upper
        else { return 0 ..< 0 }
        return lower ..< upper
    }

    /// Looks for the literal within a window around the computed offset. Bounded so
    /// a wrong guess stays local rather than matching the same word elsewhere.
    private func search(for literal: String, near computed: Range<Int>) -> Range<Int>? {
        let window = 512
        let lower = max(0, computed.lowerBound - window)
        let upper = min(source.byteCount, computed.lowerBound + window + literal.utf8.count)
        guard lower < upper, let haystack = source.slice(lower ..< upper) else { return nil }
        guard let found = haystack.range(of: literal) else { return nil }
        let offset = haystack[haystack.startIndex ..< found.lowerBound].utf8.count
        let start = lower + offset
        return start ..< (start + literal.utf8.count)
    }

    private func plainText(of markup: some Markup) -> String {
        var text = ""
        for child in markup.children {
            switch child {
            case let literal as Markdown.Text: text += literal.string
            case let code as InlineCode: text += "`\(code.code)`"
            case let strong as Strong: text += "**\(plainText(of: strong))**"
            case let emphasis as Emphasis: text += "*\(plainText(of: emphasis))*"
            case let strike as Strikethrough: text += "~~\(plainText(of: strike))~~"
            case let link as Markdown.Link:
                text += "[\(plainText(of: link))](\(link.destination ?? ""))"
            default: text += plainText(of: child)
            }
        }
        return text
    }
}
