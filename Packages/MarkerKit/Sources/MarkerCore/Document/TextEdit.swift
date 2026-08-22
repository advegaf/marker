import Foundation

/// A single splice against the raw markdown source, in UTF-8 byte offsets.
///
/// Every mutation in the app is one of these. Undo, redo, typing, inline
/// formatting, table write-back and mermaid write-back all funnel through here,
/// which is what keeps "saves clean Markdown" a property of the design rather
/// than something each call site has to remember.
public struct TextEdit: Sendable, Equatable {
    public var byteRange: Range<Int>
    public var replacement: String

    public init(byteRange: Range<Int>, replacement: String) {
        self.byteRange = byteRange
        self.replacement = replacement
    }

    /// Byte delta this edit applies to everything after `byteRange.lowerBound`.
    public var delta: Int { replacement.utf8.count - byteRange.count }

    /// The range this edit's replacement occupies once applied.
    public var appliedRange: Range<Int> {
        byteRange.lowerBound ..< (byteRange.lowerBound + replacement.utf8.count)
    }
}
