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
        let document = Document(parsing: source.text, options: [.parseBlockDirectives])
        var lowering = ASTLowering(source: source)
        lowering.visit(document)
        return Result(
            blocks: lowering.blocks,
            recoveredRunCount: lowering.recoveredRunCount,
            opaqueBlockCount: lowering.opaqueBlockCount
        )
    }
}
