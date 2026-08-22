import Foundation

/// The document's single source of truth: the raw markdown bytes on disk.
///
/// The rendered attributed string is derived output. Saving serialises `text`
/// directly, so it is a pure splice result that never consults the block index.
/// That is the safety property behind the whole editing design: a corrupted
/// source map can produce a wrong render, but never a wrong save.
public struct MarkdownSource: Sendable {
    public private(set) var text: String
    public private(set) var lineIndex: LineIndex

    public init(_ text: String) {
        self.text = text
        self.lineIndex = LineIndex(text)
    }

    public var byteCount: Int { text.utf8.count }

    /// The bytes in `range`, or nil if the range is out of bounds or lands
    /// mid-scalar. Callers treat nil as "the source map is wrong here" rather
    /// than crashing, which is what makes verify-by-slice recovery possible.
    public func slice(_ range: Range<Int>) -> String? {
        guard range.lowerBound >= 0, range.upperBound <= byteCount,
              range.lowerBound <= range.upperBound else { return nil }
        let utf8 = Array(text.utf8)
        return String(bytes: utf8[range], encoding: .utf8)
    }

    /// Applies a splice and returns the inverse edit, for the undo stack.
    @discardableResult
    public mutating func apply(_ edit: TextEdit) -> TextEdit {
        var utf8 = Array(text.utf8)
        let clamped = max(0, min(edit.byteRange.lowerBound, utf8.count))
            ..< max(0, min(edit.byteRange.upperBound, utf8.count))
        let removed = String(bytes: utf8[clamped], encoding: .utf8) ?? ""
        utf8.replaceSubrange(clamped, with: Array(edit.replacement.utf8))
        text = String(bytes: utf8, encoding: .utf8) ?? text
        lineIndex = LineIndex(text)
        return TextEdit(
            byteRange: clamped.lowerBound ..< (clamped.lowerBound + edit.replacement.utf8.count),
            replacement: removed
        )
    }
}
