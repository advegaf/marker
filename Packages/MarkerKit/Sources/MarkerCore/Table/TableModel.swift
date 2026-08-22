import Foundation

/// A GFM table, kept as data rather than as markdown text.
///
/// Every table edit regenerates the whole table's markdown from this model, so no
/// per-cell source range ever has to exist. That is what keeps cell editing free
/// of the range-mapping bug class the rest of the editor has to handle carefully.
public struct TableModel: Sendable, Equatable {

    public enum Alignment: String, Sendable, Equatable {
        case none, left, center, right
    }

    public struct Column: Sendable, Equatable {
        public var header: String
        public var alignment: Alignment

        public init(header: String, alignment: Alignment = .none) {
            self.header = header
            self.alignment = alignment
        }
    }

    public var columns: [Column]
    /// Body rows. Each row is padded or trimmed to `columns.count` on write.
    public var rows: [[String]]

    public init(columns: [Column], rows: [[String]]) {
        self.columns = columns
        self.rows = rows
    }
}
