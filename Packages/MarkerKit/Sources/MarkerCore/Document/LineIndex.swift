import Foundation

/// UTF-8 byte offset of the start of each line.
///
/// Exists to convert swift-markdown's `SourceLocation` into our byte space.
/// `SourceLocation.column` is documented as a 1-based UTF-8 byte offset from the
/// line start, so the conversion is a single addition. Getting this wrong is the
/// entire emoji and CJK corruption bug class, hence its own type and its own tests.
public struct LineIndex: Sendable {
    public private(set) var lineStarts: [Int]
    private let byteCount: Int

    public init(_ source: String) {
        self.init(bytes: Array(source.utf8))
    }

    public init(bytes: [UInt8]) {
        var starts = [0]
        var offset = 0
        for byte in bytes {
            offset += 1
            // Treat LF as the line break. A CRLF file leaves the CR at the end of
            // the previous line, which is what cmark does too, so columns still line up.
            if byte == 0x0A { starts.append(offset) }
        }
        self.lineStarts = starts
        self.byteCount = offset
    }

    public var lineCount: Int { lineStarts.count }

    /// Byte offset for a 1-based line and 1-based column, both as cmark reports them.
    /// Returns nil when the location is outside the source, which is how a caller
    /// distinguishes "cmark gave us something impossible" from a real offset.
    public func byteOffset(line: Int, column: Int) -> Int? {
        guard line >= 1, line <= lineStarts.count, column >= 1 else { return nil }
        let offset = lineStarts[line - 1] + (column - 1)
        guard offset <= byteCount else { return nil }
        return offset
    }
}
