import AppKit
import MarkerCore

/// Turns parsed blocks into the attributed string the text view displays.
///
/// One paragraph per block, which is what makes a caret map to exactly one block
/// and keeps the re-render tiers able to replace a single paragraph's range.
public struct AttributedBuilder {

    public var theme: MarkerTheme
    public var mode: RenderMode

    public init(theme: MarkerTheme, mode: RenderMode) {
        self.theme = theme
        self.mode = mode
    }

    public struct Output {
        public var attributed: NSAttributedString
        public var index: BlockIndex
    }

    public func build(_ blocks: [BlockNode]) -> Output {
        let output = NSMutableAttributedString()
        var entries: [BlockIndex.Entry] = []

        for (position, block) in blocks.enumerated() {
            let start = output.length
            let prefix = listMarker(for: block)?.utf16.count ?? 0
            let piece = attributed(block, isLast: position == blocks.count - 1)
            output.append(piece)

            // Runs sit end to end after any prefix the renderer added, so their
            // offsets fall out of their own lengths rather than needing a second pass.
            var runStarts: [Int] = []
            var cursor = start + prefix
            for run in block.runs {
                runStarts.append(cursor)
                cursor += run.renderLength
            }

            let trailingNewline = position == blocks.count - 1 ? 0 : 1
            entries.append(BlockIndex.Entry(
                blockID: block.id,
                renderStart: start,
                renderLength: piece.length - trailingNewline,
                runStarts: runStarts
            ))
        }

        return Output(
            attributed: output,
            index: BlockIndex(blocks: blocks, entries: entries)
        )
    }

    /// Newlines inside a block have to be line separators, not paragraph breaks.
    ///
    /// AppKit applies `paragraphSpacing` after every `\n`, so a ten line code fence
    /// written with newlines gets a full block gap between each line and reads as
    /// double spaced. U+2028 breaks the line without ending the paragraph, which
    /// also keeps the fence as a single `NSTextParagraph`, so the panel behind it is
    /// one layout fragment instead of ten.
    private static func lineFolded(_ text: String) -> String {
        text.replacingOccurrences(of: "\r\n", with: "\u{2028}")
            .replacingOccurrences(of: "\n", with: "\u{2028}")
    }

    // MARK: Blocks

    private func attributed(_ block: BlockNode, isLast: Bool) -> NSAttributedString {
        let piece: NSMutableAttributedString

        switch block.kind {
        case .paragraph:
            piece = inlineText(block, font: theme.bodyFont(), color: theme.colors.text)
        case .heading(let level):
            piece = inlineText(block, font: theme.headingFont(level: level), color: theme.colors.heading)
        case .codeFence(let language, let code):
            piece = codeBlock(code, language: language, block: block)
        case .mermaid(let source):
            piece = placeholder("Mermaid diagram", body: source, block: block)
        case .displayMath(let latex):
            piece = placeholder("Display math", body: latex, block: block)
        case .table(let model):
            piece = placeholder("Table", body: TableMarkdownWriter.markdown(for: model), block: block)
        case .thematicBreak:
            piece = thematicBreak(block)
        case .html(let raw):
            piece = codeBlock(raw.trimmingCharacters(in: .newlines), language: "html", block: block)
        case .opaque(let raw):
            piece = codeBlock(raw, language: nil, block: block)
        }

        piece.addAttribute(.markerBlock, value: block.id.value,
                           range: NSRange(location: 0, length: piece.length))
        if !isLast {
            piece.append(NSAttributedString(string: "\n", attributes: piece.attributes(
                at: max(piece.length - 1, 0), effectiveRange: nil
            )))
        }
        return piece
    }

    /// A block whose real renderer has not landed yet. Shows the source so the page
    /// stays complete and honest rather than leaving a hole where a feature will go.
    private func placeholder(_ label: String, body: String, block: BlockNode) -> NSMutableAttributedString {
        let text = NSMutableAttributedString(
            string: label + "\u{2028}" + Self.lineFolded(body),
            attributes: [
                .font: theme.monoFont(scale: 0.85),
                .foregroundColor: theme.colors.secondaryText,
                .paragraphStyle: blockParagraphStyle(block, indent: theme.bodyPointSize),
                .markerDecoration: MarkerDecoration.placeholder,
            ]
        )
        text.addAttributes(
            [.font: theme.monoFont(scale: 0.75), .foregroundColor: theme.colors.link],
            range: NSRange(location: 0, length: label.count)
        )
        return text
    }

    private func codeBlock(_ code: String, language: String?, block: BlockNode) -> NSMutableAttributedString {
        NSMutableAttributedString(string: Self.lineFolded(code), attributes: [
            .font: theme.monoFont(),
            .foregroundColor: theme.colors.text,
            .paragraphStyle: blockParagraphStyle(block, indent: theme.bodyPointSize),
            .markerDecoration: MarkerDecoration.codeBlock,
        ])
    }

    private func thematicBreak(_ block: BlockNode) -> NSMutableAttributedString {
        // A single space carrying the decoration, so the rule is drawn rather than
        // spelled with box-drawing characters that never line up.
        NSMutableAttributedString(string: " ", attributes: [
            .font: theme.bodyFont(),
            .foregroundColor: NSColor.clear,
            .paragraphStyle: blockParagraphStyle(block, indent: 0),
            .markerDecoration: MarkerDecoration.thematicBreak,
        ])
    }

    // MARK: Inline

    private func inlineText(_ block: BlockNode, font: NSFont, color: NSColor) -> NSMutableAttributedString {
        let output = NSMutableAttributedString()
        let style = blockParagraphStyle(block, indent: 0)

        if let marker = listMarker(for: block) {
            output.append(NSAttributedString(string: marker, attributes: [
                .font: font,
                .foregroundColor: theme.colors.secondaryText,
                .paragraphStyle: style,
            ]))
        }

        for run in block.runs {
            var attributes: [NSAttributedString.Key: Any] = [
                .font: self.font(for: run.style, base: font),
                .foregroundColor: run.linkURL != nil ? theme.colors.link : color,
                .paragraphStyle: style,
                .markerRun: run.id.value,
            ]
            if run.style.contains(.strikethrough) {
                attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
                attributes[.strikethroughColor] = color
            }
            if let url = run.linkURL {
                attributes[.link] = url
                attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
                attributes[.underlineColor] = theme.colors.link.withAlphaComponent(0.4)
            }
            if run.style.contains(.code) {
                attributes[.backgroundColor] = theme.colors.codeBackground
            }
            output.append(NSAttributedString(string: run.text, attributes: attributes))
        }

        if output.length == 0 {
            // An empty block still needs one character to carry its paragraph style.
            output.append(NSAttributedString(string: "", attributes: [
                .font: font, .foregroundColor: color, .paragraphStyle: style,
            ]))
        }
        if block.context.quoteDepth > 0 {
            output.addAttribute(
                .markerDecoration,
                value: MarkerDecoration.quote(depth: block.context.quoteDepth),
                range: NSRange(location: 0, length: output.length)
            )
        }
        return output
    }

    private func listMarker(for block: BlockNode) -> String? {
        guard block.context.isListItemStart else { return nil }
        if let checked = block.context.checked {
            return checked ? "\u{2611}  " : "\u{2610}  "
        }
        if let ordinal = block.context.ordinal {
            return "\(ordinal).  "
        }
        // Depth 1 filled, depth 2 hollow, depth 3+ square, the way every outline
        // has done it since paper.
        switch block.context.listDepth {
        case 0, 1: return "\u{2022}  "
        case 2: return "\u{25E6}  "
        default: return "\u{25AA}  "
        }
    }

    /// Bold and italic have to be asked for as traits, because the system face has
    /// no italic member that `systemFont(ofSize:weight:)` can reach.
    private func font(for style: InlineStyle, base: NSFont) -> NSFont {
        if style.contains(.code) {
            return theme.monoFont(scale: base.pointSize / theme.bodyPointSize * 0.92)
        }
        var traits: NSFontDescriptor.SymbolicTraits = []
        if style.contains(.strong) { traits.insert(.bold) }
        if style.contains(.emphasis) { traits.insert(.italic) }
        guard !traits.isEmpty else { return base }
        let descriptor = base.fontDescriptor.withSymbolicTraits(
            base.fontDescriptor.symbolicTraits.union(traits)
        )
        return NSFont(descriptor: descriptor, size: base.pointSize) ?? base
    }

    // MARK: Paragraph geometry

    private func blockParagraphStyle(_ block: BlockNode, indent: CGFloat) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        // Set the line box explicitly rather than with lineHeightMultiple. A
        // multiplier compounds with the font's own leading, and the monospaced face
        // has much more of it than the text face, so code ends up looking
        // double-spaced next to prose set from the same number.
        let leading = lineHeight(for: block.kind)
        style.minimumLineHeight = leading
        style.maximumLineHeight = leading

        let unit = theme.bodyPointSize * 1.6
        let listIndent = CGFloat(block.context.listDepth) * unit
        let quoteIndent = CGFloat(block.context.quoteDepth) * unit
        let base = listIndent + quoteIndent + indent

        style.firstLineHeadIndent = base
        // Continuation lines line up under the text, not under the bullet.
        style.headIndent = base + (block.context.isListItemStart ? unit * 0.75 : 0)
        style.paragraphSpacing = block.context.listDepth > 0
            ? theme.metrics.paragraphSpacing * 0.35 * theme.zoom
            : spacing(for: block.kind)

        if case .heading(let level) = block.kind {
            style.paragraphSpacingBefore = theme.bodyPointSize * (level <= 2 ? 1.6 : 1.1)
        }
        return style
    }

    private func lineHeight(for kind: BlockKind) -> CGFloat {
        switch kind {
        case .heading(let level): return theme.headingFont(level: level).pointSize * 1.25
        case .codeFence, .mermaid, .displayMath, .table, .html, .opaque:
            return theme.monoFont().pointSize * 1.45
        default: return theme.bodyPointSize * 1.55
        }
    }

    private func spacing(for kind: BlockKind) -> CGFloat {
        switch kind {
        case .heading: return theme.bodyPointSize * 0.5
        case .thematicBreak: return theme.metrics.blockSpacing * theme.zoom
        case .paragraph: return theme.metrics.paragraphSpacing * theme.zoom
        // Panelled blocks need clearance for the panel the text view paints behind
        // them, or two adjacent code fences read as one block with a seam.
        default: return theme.metrics.blockSpacing * 1.4 * theme.zoom
        }
    }
}
