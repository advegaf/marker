import AppKit
import MarkerCore

/// Measures and draws a GFM table.
///
/// One routine, used by both render modes. The `.image` path rasterises it and
/// the `.interactive` path will draw the same geometry behind live cell editing,
/// so a table cannot visually jump when it becomes editable. A test compares the
/// two bitmaps to keep that true.
public struct TableLayout {

    public struct Metrics {
        public var columnWidths: [CGFloat]
        public var rowHeights: [CGFloat]
        public var size: CGSize
        /// Row 0 is the header; body rows follow.
        public var rowCount: Int { rowHeights.count }
    }

    public let model: TableModel
    public let theme: MarkerTheme
    public let maxWidth: CGFloat

    private let cellPadding: CGFloat
    private let cells: [[NSAttributedString]]

    public init(model: TableModel, theme: MarkerTheme, maxWidth: CGFloat) {
        self.model = model
        self.theme = theme
        self.maxWidth = maxWidth
        self.cellPadding = theme.bodyPointSize * 0.6

        // Cell text is markdown, so `**Free**` has to arrive as bold rather than as
        // four visible asterisks. Each cell goes through the same parser the rest of
        // the document uses, which is a handful of tiny parses and reuses everything
        // instead of growing a second inline renderer.
        let columnCount = model.columns.count
        var rows: [[NSAttributedString]] = []
        rows.append(model.columns.map {
            CellText.render($0.header, theme: theme, bold: true)
        })
        for row in model.rows {
            rows.append((0 ..< columnCount).map { index in
                CellText.render(index < row.count ? row[index] : "", theme: theme, bold: false)
            })
        }
        self.cells = rows
    }

    // MARK: Measuring

    public func measure() -> Metrics {
        let columnCount = max(model.columns.count, 1)

        // Natural width first: what each column would take if nothing constrained it.
        var natural = [CGFloat](repeating: 0, count: columnCount)
        for row in cells {
            for (index, cell) in row.enumerated() where index < columnCount {
                natural[index] = max(natural[index], cell.size().width + cellPadding * 2)
            }
        }

        let total = natural.reduce(0, +)
        var widths = natural
        if total > maxWidth, total > 0 {
            // Shrink proportionally rather than truncating, and floor each column so
            // a narrow one does not collapse to nothing while a wide one keeps most
            // of the space.
            let floorWidth = min(theme.bodyPointSize * 4, maxWidth / CGFloat(columnCount))
            let scale = maxWidth / total
            widths = natural.map { max($0 * scale, floorWidth) }
            let scaled = widths.reduce(0, +)
            if scaled > maxWidth {
                widths = widths.map { $0 * (maxWidth / scaled) }
            }
        }

        // Heights come from wrapping each cell into its final column width.
        var heights: [CGFloat] = []
        for row in cells {
            var height = theme.bodyPointSize
            for (index, cell) in row.enumerated() where index < columnCount {
                let available = widths[index] - cellPadding * 2
                height = max(height, cell.boundingRect(
                    with: CGSize(width: max(available, 1), height: .greatestFiniteMagnitude),
                    options: [.usesLineFragmentOrigin, .usesFontLeading]
                ).height)
            }
            heights.append(height + cellPadding * 2)
        }

        return Metrics(
            columnWidths: widths,
            rowHeights: heights,
            size: CGSize(width: widths.reduce(0, +), height: heights.reduce(0, +))
        )
    }

    // MARK: Drawing

    /// Draws into the current context, with the origin at the table's top left in a
    /// flipped coordinate space.
    public func draw(in rect: CGRect, metrics: Metrics) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let radius = theme.metrics.codeCornerRadius

        let outline = NSBezierPath(
            roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: radius, yRadius: radius
        )

        // Header fill is clipped to the rounded outline so its top corners follow the
        // border instead of poking through it.
        context.saveGState()
        outline.addClip()
        theme.colors.tableHeaderBackground.setFill()
        CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: metrics.rowHeights[0]).fill()
        context.restoreGState()

        theme.colors.tableBorder.setStroke()
        outline.lineWidth = 1
        outline.stroke()

        // Row separators.
        var y = rect.minY
        for height in metrics.rowHeights.dropLast() {
            y += height
            let line = NSBezierPath()
            line.move(to: CGPoint(x: rect.minX, y: y))
            line.line(to: CGPoint(x: rect.maxX, y: y))
            line.lineWidth = 1
            theme.colors.tableBorder.setStroke()
            line.stroke()
        }

        // Column separators.
        var x = rect.minX
        for width in metrics.columnWidths.dropLast() {
            x += width
            let line = NSBezierPath()
            line.move(to: CGPoint(x: x, y: rect.minY))
            line.line(to: CGPoint(x: x, y: rect.maxY))
            line.lineWidth = 1
            theme.colors.tableBorder.setStroke()
            line.stroke()
        }

        // Cells.
        var rowY = rect.minY
        for (rowIndex, row) in cells.enumerated() {
            var cellX = rect.minX
            for (columnIndex, cell) in row.enumerated() where columnIndex < metrics.columnWidths.count {
                let width = metrics.columnWidths[columnIndex]
                let box = CGRect(
                    x: cellX + cellPadding,
                    y: rowY + cellPadding,
                    width: max(width - cellPadding * 2, 1),
                    height: max(metrics.rowHeights[rowIndex] - cellPadding * 2, 1)
                )
                draw(cell, in: box, alignment: model.columns[columnIndex].alignment)
                cellX += width
            }
            rowY += metrics.rowHeights[rowIndex]
        }
    }

    private func draw(_ cell: NSAttributedString, in box: CGRect, alignment: TableModel.Alignment) {
        let paragraph = NSMutableParagraphStyle()
        switch alignment {
        case .none, .left: paragraph.alignment = .left
        case .center: paragraph.alignment = .center
        case .right: paragraph.alignment = .right
        }
        let aligned = NSMutableAttributedString(attributedString: cell)
        aligned.addAttribute(.paragraphStyle, value: paragraph,
                             range: NSRange(location: 0, length: aligned.length))
        aligned.draw(with: box, options: [.usesLineFragmentOrigin, .usesFontLeading])
    }

    /// Rasterises the table, for `.image` mode and for the snapshot harness.
    public func image() -> NSImage? {
        let metrics = measure()
        guard metrics.size.width > 1, metrics.size.height > 1 else { return nil }

        let image = NSImage(size: metrics.size)
        image.lockFocusFlipped(true)
        draw(in: CGRect(origin: .zero, size: metrics.size), metrics: metrics)
        image.unlockFocus()
        return image
    }
}

/// Cell markdown to styled text, cached because a table re-renders on every
/// keystroke once editing lands and most cells never change.
private enum CellText {
    private static let cache = NSCache<NSString, NSAttributedString>()

    static func render(_ markdown: String, theme: MarkerTheme, bold: Bool) -> NSAttributedString {
        let key = "\(bold)|\(theme.bodyPointSize)|\(theme.isDark)|\(markdown)" as NSString
        if let cached = cache.object(forKey: key) { return cached }

        let parsed = MarkdownParser.parse(MarkdownSource(markdown))
        let font = bold
            ? NSFont.systemFont(ofSize: theme.bodyPointSize * 0.95, weight: .semibold)
            : NSFont.systemFont(ofSize: theme.bodyPointSize * 0.95)

        let output = NSMutableAttributedString()
        for block in parsed.blocks {
            for run in block.runs {
                var attributes: [NSAttributedString.Key: Any] = [
                    .font: font,
                    .foregroundColor: run.linkURL != nil ? theme.colors.link : theme.colors.text,
                ]
                if run.style.contains(.code) {
                    attributes[.font] = theme.monoFont(scale: 0.85)
                    attributes[.backgroundColor] = theme.colors.codeBackground
                }
                if run.style.contains(.strong) || bold {
                    attributes[.font] = NSFont.systemFont(
                        ofSize: theme.bodyPointSize * 0.95, weight: .semibold
                    )
                }
                if run.style.contains(.strikethrough) {
                    attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
                }
                output.append(NSAttributedString(string: run.text, attributes: attributes))
            }
        }
        if output.length == 0 {
            output.append(NSAttributedString(string: markdown, attributes: [.font: font]))
        }
        cache.setObject(output, forKey: key)
        return output
    }
}
