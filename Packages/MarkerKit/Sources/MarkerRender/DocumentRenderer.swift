import AppKit
import MarkerCore

/// How much of the document becomes live views.
///
/// `.image` instantiates zero `NSView`s, which is what makes Quick Look, PDF
/// export and the offscreen screenshot harness work without fighting layer-backed
/// capture. `.interactive` swaps tables for editable views and is only ever used
/// by the Pro editor.
public enum RenderMode: Sendable {
    case image
    case interactive
}

public struct RenderedDocument {
    public var attributed: NSAttributedString
    public var index: BlockIndex
    public var blocks: [BlockNode]
    public var recoveredRunCount: Int
    public var opaqueBlockCount: Int
}

public struct DocumentRenderer {
    public var theme: MarkerTheme
    public var mode: RenderMode

    public init(theme: MarkerTheme, mode: RenderMode) {
        self.theme = theme
        self.mode = mode
    }

    public func renderDocument(_ source: MarkdownSource) -> RenderedDocument {
        let parsed = MarkdownParser.parse(source)
        let built = AttributedBuilder(theme: theme, mode: mode).build(parsed.blocks)
        return RenderedDocument(
            attributed: built.attributed,
            index: built.index,
            blocks: parsed.blocks,
            recoveredRunCount: parsed.recoveredRunCount,
            opaqueBlockCount: parsed.opaqueBlockCount
        )
    }

    public func render(_ source: MarkdownSource) -> NSAttributedString {
        renderDocument(source).attributed
    }

    /// Plain text with syntax colouring rather than markdown structure, for the
    /// file types the FAQ promises: plain text, and pretty-printed JSON and YAML.
    public func renderPlain(_ text: String) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineHeightMultiple = 1.35
        return NSAttributedString(string: text, attributes: [
            .font: theme.monoFont(),
            .foregroundColor: theme.colors.text,
            .paragraphStyle: paragraph,
        ])
    }
}
