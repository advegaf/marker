import Foundation

/// Turns a change made to the rendered text into an edit against the source.
///
/// This is the hinge of WYSIWYG editing and the place a mistake corrupts a file,
/// so it lives here, in a type with no AppKit in it, where it can be tested
/// directly instead of through a text view.
///
/// The rule it enforces: an edit is only mapped when it lands somewhere the map can
/// account for. Anything ambiguous is refused rather than guessed at, and the
/// caller falls back to leaving the source alone and re-rendering, which loses a
/// keystroke instead of corrupting a document.
public enum EditMapper {

    public enum Refusal: Error, Equatable {
        /// The edit touched rendered text that no source range produced: a list
        /// bullet, an ordinal, a checkbox, the space after them.
        case syntheticText
        /// The edit spanned two blocks, or a block boundary.
        case crossesBlocks
        /// The edit landed on an attachment: a table, a diagram, a formula. Those
        /// are edited through their own surfaces, not by typing over them.
        case attachment
        /// The block does not carry a usable source map.
        case opaqueBlock
    }

    public struct Mapped: Equatable {
        public let edit: TextEdit
        /// Where the caret should land, in source bytes.
        public let caret: Int
    }

    /// Maps a replacement of `renderRange` with `replacement`.
    ///
    /// `renderRange` is in UTF-16 offsets against the rendered string as it was
    /// *before* the change, which is the only coordinate space AppKit reports.
    public static func map(
        renderRange: Range<Int>,
        replacement: String,
        index: BlockIndex,
        source: MarkdownSource
    ) -> Result<Mapped, Refusal> {
        guard let startBlock = index.blockIndex(forRender: renderRange.lowerBound) else {
            return .failure(.crossesBlocks)
        }
        // An empty range is an insertion; its end is its start.
        let endProbe = max(renderRange.upperBound - 1, renderRange.lowerBound)
        guard let endBlock = index.blockIndex(forRender: endProbe), endBlock == startBlock else {
            return .failure(.crossesBlocks)
        }

        let block = index.blocks[startBlock]
        if case .opaque = block.kind { return .failure(.opaqueBlock) }
        // Tables, diagrams and formulas are single attachment characters in the
        // rendered string. Typing over one would replace the whole thing with a
        // letter, so they are refused here and edited through their own surfaces.
        switch block.kind {
        case .table, .mermaid, .displayMath, .thematicBreak, .html:
            return .failure(.attachment)
        case .paragraph, .heading, .codeFence:
            break
        case .opaque:
            return .failure(.opaqueBlock)
        }

        guard let lower = sourceOffset(forRender: renderRange.lowerBound, block: block, entry: index.entries[startBlock]),
              let upper = sourceOffset(forRender: renderRange.upperBound, block: block, entry: index.entries[startBlock], isEnd: true)
        else { return .failure(.syntheticText) }

        guard lower <= upper, upper <= source.byteCount else { return .failure(.syntheticText) }

        return .success(Mapped(
            edit: TextEdit(byteRange: lower ..< upper, replacement: replacement),
            caret: lower + replacement.utf8.count
        ))
    }

    /// UTF-8 byte offset matching a UTF-16 offset inside `text`.
    ///
    /// Returns nil when the offset lands in the middle of a surrogate pair, which is
    /// not a position a caret can occupy and is not something to round.
    static func utf8Offset(forUTF16 offset: Int, in text: String) -> Int? {
        if offset == 0 { return 0 }
        guard offset > 0 else { return nil }
        var utf16Seen = 0
        var utf8Seen = 0
        for character in text {
            if utf16Seen == offset { return utf8Seen }
            utf16Seen += character.utf16.count
            utf8Seen += String(character).utf8.count
            if utf16Seen > offset { return nil }
        }
        return utf16Seen == offset ? utf8Seen : nil
    }

    /// Maps one render offset into the source, inside a known block.
    ///
    /// Returns nil when the offset falls in text the renderer invented: a bullet, an
    /// ordinal, a checkbox. Those have no source to edit, and mapping them to the
    /// nearest run would let a keystroke land in the wrong place.
    static func sourceOffset(
        forRender offset: Int,
        block: BlockNode,
        entry: BlockIndex.Entry,
        isEnd: Bool = false
    ) -> Int? {
        guard !block.runs.isEmpty else { return nil }

        for (position, run) in block.runs.enumerated() {
            let start = entry.runStarts[position]
            let end = start + run.renderLength
            // An end offset is inclusive of the run's end, so typing at the end of a
            // word extends the word rather than starting a new one. It is inclusive
            // of the start too: an empty range at a run's start is an insertion
            // before it, and treating that as "past the last run" turned every
            // insertion at a block's start into a replacement of the whole block.
            let inside = isEnd ? (offset >= start && offset <= end) : (offset >= start && offset < end)
            guard inside else { continue }

            let into = offset - start

            // Math runs cover their `$` delimiters, so an offset inside one is a
            // position in a formula, not a character position in the source.
            if run.style.contains(.math) {
                return into == 0 ? run.sourceRange.lowerBound : run.sourceRange.upperBound
            }

            // The two spaces count differently: rendered text is UTF-16, source is
            // UTF-8. An emoji is two units against four bytes, so carrying the offset
            // across unconverted lands mid-character and splits it.
            guard let byteOffset = OffsetConversion.utf8Offset(forUTF16: into, in: run.text) else { return nil }

            // Only safe when the run's text is literally its source bytes. An escape
            // or a folded newline means the two differ character by character, and
            // then only the edges can be placed.
            guard run.sourceRange.count == run.text.utf8.count else {
                if into == 0 { return run.sourceRange.lowerBound }
                if into == run.renderLength { return run.sourceRange.upperBound }
                return nil
            }
            return run.sourceRange.lowerBound + byteOffset
        }

        // Genuinely past the last run, which is where typing at the end of a
        // paragraph lands.
        if let last = block.runs.last {
            let lastEnd = entry.runStarts[block.runs.count - 1] + last.renderLength
            if offset >= lastEnd { return last.sourceRange.upperBound }
        }
        return nil
    }
}
