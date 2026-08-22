import Foundation

/// Regenerates a whole GFM table from its model.
///
/// Every table edit goes through here rather than patching cells in place, which
/// is why no per-cell source range ever has to exist. Cells are padded to the
/// column's widest content so the raw markdown stays readable in a diff.
public enum TableMarkdownWriter {

    public static func markdown(for model: TableModel) -> String {
        guard !model.columns.isEmpty else { return "" }

        let headers = model.columns.map { escape($0.header) }
        let rows = model.rows.map { row in
            (0 ..< model.columns.count).map { index in
                index < row.count ? escape(row[index]) : ""
            }
        }

        let widths = (0 ..< model.columns.count).map { index -> Int in
            let cells = [headers[index]] + rows.map { $0[index] }
            // The delimiter row needs at least three dashes plus its colons.
            return max(cells.map { $0.count }.max() ?? 3, 3)
        }

        var lines = [row(headers, widths: widths)]
        lines.append(delimiterRow(model.columns.map(\.alignment), widths: widths))
        lines.append(contentsOf: rows.map { row($0, widths: widths) })
        return lines.joined(separator: "\n")
    }

    private static func row(_ cells: [String], widths: [Int]) -> String {
        let padded = zip(cells, widths).map { cell, width in
            cell.padding(toLength: max(width, cell.count), withPad: " ", startingAt: 0)
        }
        return "| " + padded.joined(separator: " | ") + " |"
    }

    private static func delimiterRow(_ alignments: [TableModel.Alignment], widths: [Int]) -> String {
        let cells = zip(alignments, widths).map { alignment, width -> String in
            switch alignment {
            case .none: return String(repeating: "-", count: width)
            case .left: return ":" + String(repeating: "-", count: width - 1)
            case .right: return String(repeating: "-", count: width - 1) + ":"
            case .center: return ":" + String(repeating: "-", count: width - 2) + ":"
            }
        }
        return "| " + cells.joined(separator: " | ") + " |"
    }

    /// A literal pipe inside a cell would end the cell, so it has to be escaped.
    private static func escape(_ cell: String) -> String {
        cell.replacingOccurrences(of: "|", with: "\\|")
            .replacingOccurrences(of: "\n", with: " ")
    }
}
