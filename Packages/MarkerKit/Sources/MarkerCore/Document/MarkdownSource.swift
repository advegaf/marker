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

    /// The UTF-8 bytes, held rather than recomputed.
    ///
    /// `slice` is called once per inline run during lowering, and rebuilding the
    /// byte array each time made parsing quadratic in document size: a 367 KB file
    /// took 100 ms to lower, against 6 ms once this was stored. Holding it costs one
    /// extra copy of the document in memory and turns the whole thing linear.
    private var bytes: [UInt8]

    public init(_ text: String) {
        let utf8 = Array(text.utf8)
        self.text = text
        self.bytes = utf8
        self.lineIndex = LineIndex(bytes: utf8)
    }

    public var byteCount: Int { bytes.count }

    /// The bytes in `range`, or nil if the range is out of bounds or lands
    /// mid-scalar. Callers treat nil as "the source map is wrong here" rather
    /// than crashing, which is what makes verify-by-slice recovery possible.
    public func slice(_ range: Range<Int>) -> String? {
        guard range.lowerBound >= 0, range.upperBound <= bytes.count,
              range.lowerBound <= range.upperBound else { return nil }
        return String(bytes: bytes[range], encoding: .utf8)
    }

    /// Raw bytes in a range, for callers that do not need a String built.
    public func byteSlice(_ range: Range<Int>) -> ArraySlice<UInt8>? {
        guard range.lowerBound >= 0, range.upperBound <= bytes.count,
              range.lowerBound <= range.upperBound else { return nil }
        return bytes[range]
    }

    public func byte(at index: Int) -> UInt8? {
        index >= 0 && index < bytes.count ? bytes[index] : nil
    }

    /// Applies a splice and returns the inverse edit, for the undo stack.
    @discardableResult
    public mutating func apply(_ edit: TextEdit) -> TextEdit {
        let clamped = max(0, min(edit.byteRange.lowerBound, bytes.count))
            ..< max(0, min(edit.byteRange.upperBound, bytes.count))
        let removed = String(bytes: bytes[clamped], encoding: .utf8) ?? ""
        bytes.replaceSubrange(clamped, with: Array(edit.replacement.utf8))
        text = String(bytes: bytes, encoding: .utf8) ?? text
        lineIndex = LineIndex(bytes: bytes)
        return TextEdit(
            byteRange: clamped.lowerBound ..< (clamped.lowerBound + edit.replacement.utf8.count),
            replacement: removed
        )
    }
}
