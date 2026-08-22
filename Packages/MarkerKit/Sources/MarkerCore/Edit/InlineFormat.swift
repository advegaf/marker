import Foundation

/// Bold, italic, strikethrough and inline code, as edits against the source.
///
/// A toggle, not an insert: running it on text that already has the style takes it
/// off. Working out which of the two is happening is the whole job, and it is done
/// from the parsed runs rather than by looking for asterisks, because asterisks
/// appear in prose and the parser already knows which ones were markup.
public enum InlineFormat {

    public enum Style: Sendable, Equatable, CaseIterable {
        case strong
        case emphasis
        case strikethrough
        case code

        var inlineStyle: InlineStyle {
            switch self {
            case .strong: return .strong
            case .emphasis: return .emphasis
            case .strikethrough: return .strikethrough
            case .code: return .code
            }
        }

        /// The delimiter used when adding the style.
        var marker: String {
            switch self {
            case .strong: return "**"
            case .emphasis: return "_"
            case .strikethrough: return "~~"
            case .code: return "`"
            }
        }

        /// Every character that can delimit this style, for recognising one that is
        /// already there. Bold and italic can be written with either mark.
        var markerCharacters: Set<Character> {
            switch self {
            case .strong, .emphasis: return ["*", "_"]
            case .strikethrough: return ["~"]
            case .code: return ["`"]
            }
        }
    }

    public enum Refusal: Error, Equatable {
        case emptySelection
        case crossesBlocks
        /// The selection covers text with no source behind it, or a block that
        /// cannot carry inline styling.
        case notFormattable
    }

    public struct Result: Equatable {
        /// Applied in order. Later offsets come first, so earlier ones stay valid.
        public let edits: [TextEdit]
        /// The selection afterwards, in source bytes.
        public let selection: Range<Int>
        public let didRemove: Bool
    }

    /// Toggles `style` over a source byte range.
    public static func toggle(
        _ style: Style,
        over range: Range<Int>,
        in source: MarkdownSource,
        blocks: [BlockNode]
    ) -> Swift.Result<Result, Refusal> {
        guard !range.isEmpty else { return .failure(.emptySelection) }

        let covering = blocks.filter { $0.sourceRange.overlaps(range) }
        guard covering.count == 1, let block = covering.first else {
            return .failure(.crossesBlocks)
        }
        switch block.kind {
        case .paragraph, .heading: break
        default: return .failure(.notFormattable)
        }

        let touched = block.runs.filter { $0.sourceRange.overlaps(range) }
        guard !touched.isEmpty else { return .failure(.notFormattable) }

        // Already styled end to end means this is a removal.
        if touched.allSatisfy({ $0.style.contains(style.inlineStyle) }),
           let inner = span(of: touched),
           let delimiters = delimiters(for: style, around: inner, in: source) {
            return .success(Result(
                edits: [
                    // Later first, so the earlier offset is still valid when it runs.
                    TextEdit(byteRange: delimiters.close, replacement: ""),
                    TextEdit(byteRange: delimiters.open, replacement: ""),
                ],
                selection: (inner.lowerBound - delimiters.open.count)
                    ..< (inner.upperBound - delimiters.open.count),
                didRemove: true
            ))
        }

        let marker = openingMarker(for: style, over: range, in: source)
        return .success(Result(
            edits: [
                TextEdit(byteRange: range.upperBound ..< range.upperBound, replacement: marker.close),
                TextEdit(byteRange: range.lowerBound ..< range.lowerBound, replacement: marker.open),
            ],
            selection: (range.lowerBound + marker.open.utf8.count)
                ..< (range.upperBound + marker.open.utf8.count),
            didRemove: false
        ))
    }

    /// Whether the style is on, for ticking a menu item.
    public static func isActive(
        _ style: Style, over range: Range<Int>, blocks: [BlockNode]
    ) -> Bool {
        let touched = blocks
            .filter { $0.sourceRange.overlaps(range) }
            .flatMap(\.runs)
            .filter { $0.sourceRange.overlaps(range) }
        return !touched.isEmpty && touched.allSatisfy { $0.style.contains(style.inlineStyle) }
    }

    // MARK: Details

    private static func span(of runs: [InlineRun]) -> Range<Int>? {
        guard let lower = runs.map(\.sourceRange.lowerBound).min(),
              let upper = runs.map(\.sourceRange.upperBound).max() else { return nil }
        return lower ..< upper
    }

    /// Finds the delimiters sitting either side of already-styled content.
    ///
    /// Read off the source rather than assumed, because bold can be written with
    /// asterisks or underscores and inline code can use any number of backticks.
    private static func delimiters(
        for style: Style, around inner: Range<Int>, in source: MarkdownSource
    ) -> (open: Range<Int>, close: Range<Int>)? {
        var openStart = inner.lowerBound
        while openStart > 0,
              let byte = source.byte(at: openStart - 1),
              let character = Character(byte: byte),
              style.markerCharacters.contains(character) {
            openStart -= 1
        }
        var closeEnd = inner.upperBound
        while let byte = source.byte(at: closeEnd),
              let character = Character(byte: byte),
              style.markerCharacters.contains(character) {
            closeEnd += 1
        }

        let open = openStart ..< inner.lowerBound
        let close = inner.upperBound ..< closeEnd
        // Both sides must be present and the same length, or this is not the pair
        // that produced the style and removing it would break the document.
        guard !open.isEmpty, open.count == close.count else { return nil }
        return (open, close)
    }

    /// The delimiter to add, with the CommonMark backtick rule applied.
    private static func openingMarker(
        for style: Style, over range: Range<Int>, in source: MarkdownSource
    ) -> (open: String, close: String) {
        guard style == .code, let content = source.slice(range) else {
            return (style.marker, style.marker)
        }
        // Inline code containing a run of n backticks has to be fenced with at least
        // n+1, and padded with spaces so the fence is not absorbed into the content.
        var longest = 0
        var current = 0
        for character in content {
            current = character == "`" ? current + 1 : 0
            longest = max(longest, current)
        }
        guard longest > 0 else { return ("`", "`") }
        let fence = String(repeating: "`", count: longest + 1)
        return (fence + " ", " " + fence)
    }
}

private extension Character {
    /// ASCII byte to Character, for reading delimiters out of the source. Returns
    /// nil for anything non-ASCII, which no markdown delimiter is.
    init?(byte: UInt8) {
        guard byte < 0x80 else { return nil }
        self = Character(UnicodeScalar(byte))
    }
}
