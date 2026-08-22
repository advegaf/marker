import Foundation

/// Decides whether a byte range in the source is the thing that produced a piece
/// of rendered text.
///
/// Split out from the lowering so the tests assert against exactly the same
/// definition the lowering used. A verifier the tests reimplement is a verifier
/// that eventually disagrees with the code it is meant to be checking.
public enum SourceVerifier {

    /// Whether the bytes in `range` are what cmark turned into `literal`.
    ///
    /// A raw slice and a node's text are not required to be identical, and
    /// expecting them to be is what sends healthy paragraphs down the opaque path.
    /// cmark unescapes backslash escapes in text and folds newlines inside inline
    /// code to spaces. In both cases the range is right and only the presentation
    /// differs, which is what rendering means.
    public static func produces(_ literal: String, at range: Range<Int>, in source: MarkdownSource) -> Bool {
        // The common case, and the hot one: the bytes are already what cmark
        // reported. Comparing them directly avoids building a String for every
        // inline run in the document, which is most of the cost of lowering a large
        // file.
        if let bytes = source.byteSlice(range), bytes.elementsEqual(literal.utf8) { return true }

        guard let raw = source.slice(range) else { return false }
        let folded = raw
            .replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
        if folded == literal { return true }
        if unescaped(raw) == literal { return true }
        if unescaped(folded) == literal { return true }
        return false
    }

    /// Nudges a range that is close but wrong.
    ///
    /// swift-markdown adjusts inline-code ranges by the backtick count, and gets it
    /// off by one on both bounds when the code spans a line break. Rather than
    /// special-case that one bug, try small shifts and take the smallest one that
    /// produces the right text. Bounded to a few bytes so a genuinely wrong range
    /// is still rejected rather than snapped onto a neighbour.
    public static func correctedRange(
        for literal: String, near computed: Range<Int>, in source: MarkdownSource
    ) -> Range<Int>? {
        let deltas = [0, 1, -1, 2, -2, 3, -3]
        for lower in deltas {
            for upper in deltas {
                let start = computed.lowerBound + lower
                let end = computed.upperBound + upper
                guard start >= 0, start <= end, end <= source.byteCount else { continue }
                if produces(literal, at: start ..< end, in: source) { return start ..< end }
            }
        }
        return nil
    }

    /// CommonMark backslash escapes: a backslash before ASCII punctuation is dropped.
    static func unescaped(_ text: String) -> String {
        guard text.contains("\\") else { return text }
        let punctuation = Set(##"!"#$%&'()*+,-./:;<=>?@[\]^_`{|}~"##)
        var out = ""
        var escaping = false
        for character in text {
            if escaping {
                if !punctuation.contains(character) { out.append("\\") }
                out.append(character)
                escaping = false
            } else if character == "\\" {
                escaping = true
            } else {
                out.append(character)
            }
        }
        if escaping { out.append("\\") }
        return out
    }
}
