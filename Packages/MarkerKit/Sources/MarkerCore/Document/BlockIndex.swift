import Foundation

/// Bidirectional map between the raw markdown (UTF-8 bytes) and the rendered
/// string (UTF-16 offsets, which is what AppKit counts in).
///
/// This is the spine of editing, find and copy. It is deliberately a value type
/// built alongside the attributed string, so the two can never drift apart: if the
/// render is rebuilt, so is the index.
public struct BlockIndex: Sendable {

    /// Where one block's rendered text sits, and where each of its runs starts.
    public struct Entry: Sendable {
        public var blockID: BlockID
        /// UTF-16 offset of the block's first character in the rendered string.
        public var renderStart: Int
        /// UTF-16 length of the block's rendered text, the trailing newline excluded.
        public var renderLength: Int
        /// UTF-16 offset of each run, parallel to the block's `runs`. Any prefix the
        /// renderer added (a bullet, an ordinal, a checkbox) sits before the first.
        public var runStarts: [Int]

        public init(blockID: BlockID, renderStart: Int, renderLength: Int, runStarts: [Int]) {
            self.blockID = blockID
            self.renderStart = renderStart
            self.renderLength = renderLength
            self.runStarts = runStarts
        }

        public var renderRange: Range<Int> { renderStart ..< (renderStart + renderLength) }
    }

    public private(set) var blocks: [BlockNode]
    public private(set) var entries: [Entry]

    public init(blocks: [BlockNode], entries: [Entry]) {
        self.blocks = blocks
        self.entries = entries
    }

    public static let empty = BlockIndex(blocks: [], entries: [])

    // MARK: Lookup

    /// Index of the block containing a rendered offset. Binary search on the block
    /// starts, then a linear scan of that block's runs, which are few.
    public func blockIndex(forRender offset: Int) -> Int? {
        guard !entries.isEmpty else { return nil }
        var low = 0
        var high = entries.count - 1
        var found: Int?
        while low <= high {
            let mid = (low + high) / 2
            if entries[mid].renderStart <= offset {
                found = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        return found
    }

    /// The source byte offset a rendered offset maps to.
    ///
    /// Offsets inside a renderer-added prefix, and offsets past the last run, both
    /// bind to the nearest run boundary rather than returning nil, because a caret
    /// always has to land somewhere in the source.
    public func sourceOffset(forRender offset: Int) -> Int? {
        guard let index = blockIndex(forRender: offset) else { return nil }
        let entry = entries[index]
        let block = blocks[index]
        guard !block.runs.isEmpty else { return block.sourceRange.lowerBound }

        for (position, run) in block.runs.enumerated().reversed() {
            let start = entry.runStarts[position]
            guard offset >= start else { continue }
            let into = offset - start
            guard into <= run.renderLength else { return run.sourceRange.upperBound }
            // The two spaces count differently, so the offset is converted rather
            // than carried across. Clamped to the run's source afterwards, because a
            // run whose text was escaped or folded is shorter than its source and
            // the converted offset would otherwise point past it.
            guard let converted = OffsetConversion.utf8Offset(forUTF16: into, in: run.text) else {
                return run.sourceRange.lowerBound
            }
            return run.sourceRange.lowerBound + min(converted, run.sourceRange.count)
        }
        return block.runs[0].sourceRange.lowerBound
    }

    /// The rendered offset a source byte offset maps to.
    public func renderOffset(forSource offset: Int) -> Int? {
        for (index, block) in blocks.enumerated() {
            guard block.sourceRange.contains(offset) || block.sourceRange.upperBound == offset
            else { continue }
            let entry = entries[index]
            guard !block.runs.isEmpty else { return entry.renderStart }

            for (position, run) in block.runs.enumerated() {
                guard !run.sourceRange.isEmpty else { continue }
                if offset < run.sourceRange.lowerBound { return entry.runStarts[position] }
                if run.sourceRange.contains(offset) || run.sourceRange.upperBound == offset {
                    let into = offset - run.sourceRange.lowerBound
                    guard let converted = OffsetConversion.utf16Offset(forUTF8: into, in: run.text) else {
                        return entry.runStarts[position]
                    }
                    return entry.runStarts[position] + min(converted, run.renderLength)
                }
            }
            return entry.renderRange.upperBound
        }
        return nil
    }

    /// Run at a rendered offset, for the editor and for inline formatting.
    public func run(atRender offset: Int) -> (block: BlockNode, run: InlineRun)? {
        guard let index = blockIndex(forRender: offset) else { return nil }
        let block = blocks[index]
        let entry = entries[index]
        for (position, run) in block.runs.enumerated().reversed()
        where offset >= entry.runStarts[position] {
            return (block, run)
        }
        return nil
    }
}
