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
            piece = displayMath(latex, block: block)
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

    /// A centred formula on its own line, or the source in a code panel when the
    /// LaTeX does not parse. Showing the source beats showing a blank space to
    /// someone who is trying to fix a formula.
    private func displayMath(_ latex: String, block: BlockNode) -> NSMutableAttributedString {
        guard let rendered = MathRenderer.render(
            latex: latex,
            pointSize: theme.bodyPointSize * 1.25,
            color: theme.colors.text,
            display: true
        ) else {
            return codeBlock(latex, language: "latex", block: block)
        }

        let attachment = NSTextAttachment()
        attachment.image = rendered.image
        attachment.bounds = CGRect(origin: .zero, size: rendered.image.size)

        let style = NSMutableParagraphStyle()
        style.alignment = .center
        style.paragraphSpacing = theme.metrics.blockSpacing * 1.4 * theme.zoom
        style.paragraphSpacingBefore = theme.metrics.blockSpacing * 0.6 * theme.zoom

        let text = NSMutableAttributedString(attachment: attachment)
        text.addAttribute(.paragraphStyle, value: style,
                          range: NSRange(location: 0, length: text.length))
        return text
    }

    /// A formula inside a sentence, sitting on the text baseline.
    private func inlineMath(_ latex: String, font: NSFont, color: NSColor) -> NSAttributedString? {
        // Latin Modern Math has a smaller optical size than the system text face, so
        // asking for the same point size renders a formula that looks shrunken next
        // to the words around it. The multiplier matches x-heights by eye.
        guard let rendered = MathRenderer.render(
            latex: latex, pointSize: font.pointSize * 1.22, color: color, display: false
        ) else { return nil }

        let attachment = NSTextAttachment()
        attachment.image = rendered.image
        attachment.bounds = CGRect(
            x: 0, y: -rendered.descent,
            width: rendered.image.size.width, height: rendered.image.size.height
        )
        return NSAttributedString(attachment: attachment)
    }

    private func codeBlock(_ code: String, language: String?, block: BlockNode) -> NSMutableAttributedString {
        let style = blockParagraphStyle(block, indent: theme.bodyPointSize)
        let base: [NSAttributedString.Key: Any] = [
            .font: theme.monoFont(),
            .foregroundColor: theme.colors.text,
            .paragraphStyle: style,
            .markerDecoration: MarkerDecoration.codeBlock,
        ]

        let output = NSMutableAttributedString()
        // Tokens carry their text rather than ranges into the source, so appending
        // them in order cannot drift out of step with the code being highlighted.
        for token in Highlighter.tokenize(code, language: language) {
            var attributes = base
            attributes[.foregroundColor] = theme.colors.syntax.color(
                for: token.kind, plain: theme.colors.text
            )
            output.append(NSAttributedString(string: Self.lineFolded(token.text), attributes: attributes))
        }
        if output.length == 0 {
            output.append(NSAttributedString(string: Self.lineFolded(code), attributes: base))
        }
        return output
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

        if let checked = block.context.checked, block.context.isListItemStart,
           let checkbox = checkboxAttachment(checked: checked) {
            let marker = NSMutableAttributedString(attributedString: checkbox)
            marker.addAttribute(.paragraphStyle, value: style,
                                range: NSRange(location: 0, length: marker.length))
            output.append(marker)
        } else if let marker = listMarker(for: block) {
            output.append(NSAttributedString(string: marker, attributes: [
                .font: font,
                .foregroundColor: theme.colors.secondaryText,
                .paragraphStyle: style,
            ]))
        }

        for run in block.runs {
            if run.style.contains(.math) {
                if let formula = inlineMath(run.text, font: font, color: color) {
                    let piece = NSMutableAttributedString(attributedString: formula)
                    piece.addAttributes(
                        [.paragraphStyle: style, .markerRun: run.id.value],
                        range: NSRange(location: 0, length: piece.length)
                    )
                    output.append(piece)
                    continue
                }
                // Unparseable inline LaTeX falls back to its own source, set as code
                // so it is visibly not prose.
                output.append(NSAttributedString(string: "$\(run.text)$", attributes: [
                    .font: theme.monoFont(scale: font.pointSize / theme.bodyPointSize * 0.92),
                    .foregroundColor: theme.colors.secondaryText,
                    .paragraphStyle: style,
                    .markerRun: run.id.value,
                ]))
                continue
            }

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

    /// Task checkboxes are SF Symbols; bullets stay typographic.
    ///
    /// A bullet is punctuation set in the text font, so it tracks the baseline and
    /// scales with zoom for free. A checkbox is a control glyph with no good
    /// typographic equivalent, and the Unicode boxes render at wildly different
    /// weights across faces, so those become real symbols.
    private func checkboxAttachment(checked: Bool) -> NSAttributedString? {
        let name = checked ? "checkmark.square.fill" : "square"
        let configuration = NSImage.SymbolConfiguration(
            pointSize: theme.bodyPointSize, weight: .regular
        )
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: checked ? "Checked" : "Unchecked")?
            .withSymbolConfiguration(configuration) else { return nil }
        image.isTemplate = true

        let attachment = NSTextAttachment()
        attachment.image = image
        // Sit the symbol on the text baseline rather than the line box bottom, or it
        // rides low next to the label and drifts further at every zoom step.
        let font = theme.bodyFont()
        let size = image.size
        attachment.bounds = CGRect(
            x: 0,
            y: (font.capHeight - size.height) / 2,
            width: size.width,
            height: size.height
        )
        let text = NSMutableAttributedString(attachment: attachment)
        text.addAttribute(
            .foregroundColor,
            value: checked ? theme.colors.text : theme.colors.secondaryText,
            range: NSRange(location: 0, length: text.length)
        )
        text.append(NSAttributedString(string: "  "))
        return text
    }

    private func listMarker(for block: BlockNode) -> String? {
        guard block.context.isListItemStart else { return nil }
        if block.context.checked != nil {
            // Two characters: the attachment plus the gap, so the run offsets that
            // BlockIndex computes from this length stay correct.
            return "\u{FFFC}  "
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
