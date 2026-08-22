import Foundation
import Markdown

/// Parses markdown and lowers it to our value model in one step.
///
/// The two halves are deliberately not separable. swift-markdown's `Markup` is a
/// struct wrapping shared `RawMarkup` class storage and is **not** `Sendable`, so
/// a `Document` must never cross an actor boundary. Doing the parse and the
/// lowering inside one `nonisolated` function means only `[BlockNode]`, which is
/// all values, ever comes back.
public enum MarkdownParser {

    public struct Result: Sendable {
        public var blocks: [BlockNode]
        /// Counts of runs whose source range had to be corrected, and blocks that
        /// could not be trusted at all. Logged rather than assumed, so the real
        /// rate of the cmark column-drift problem is known.
        public var recoveredRunCount: Int
        public var opaqueBlockCount: Int
    }

    public static func parse(_ source: MarkdownSource) -> Result {
        // `disableSmartOpts` is not a style preference, it is a correctness requirement.
        //
        // cmark's smart punctuation rewrites the text of a node: ' becomes a curly
        // ’, " becomes “ ”, -- becomes an en dash, ... becomes an ellipsis. The
        // source range it reports still covers the original bytes, so verify-by-slice
        // compares a 3-byte ’ against a 1-byte ' and fails. The block is then marked
        // opaque and renders as raw Markdown in a monospaced panel. Any English
        // paragraph containing an apostrophe hit this, which is most of them.
        //
        // Turning it off is also the honest choice for this app: the page is meant
        // to show what is in the file. Silently displaying punctuation the author
        // did not type is exactly the normalisation that byte splicing exists to
        // avoid, and it would put multi-byte characters in the render that do not
        // exist in the source for the offset mapping to line up against.
        let document = Document(
            parsing: source.text,
            options: [.parseBlockDirectives, .disableSmartOpts]
        )
        var lowering = ASTLowering(source: source)
        lowering.visit(document)
        return Result(
            blocks: lowering.blocks,
            recoveredRunCount: lowering.recoveredRunCount,
            opaqueBlockCount: lowering.opaqueBlockCount
        )
    }
}
