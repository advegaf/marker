import AppKit
import MarkerCore

/// Custom attributed-string keys.
///
/// Deliberately few. The editor needs to map a caret back to the source, and the
/// text view needs to know which stretches get painted decoration. Absolute source
/// offsets are *not* stored per run, because they would go stale on every
/// keystroke; the run table on the block owns those.
public extension NSAttributedString.Key {
    /// Which `InlineRun` produced this stretch of text.
    static let markerRun = NSAttributedString.Key("markerRun")
    /// Which `BlockNode` produced this stretch of text.
    static let markerBlock = NSAttributedString.Key("markerBlock")
    /// Decoration the text view paints behind the glyphs.
    static let markerDecoration = NSAttributedString.Key("markerDecoration")
}

/// Painted behind the text rather than expressed as glyphs, so a code block gets a
/// full-width rounded panel and a quote gets a real bar instead of a border
/// character pretending to be one.
/// Hashable, not merely Equatable: this is stored as an attributed-string attribute
/// value, and AppKit hashes attribute values during layout. Leaving it Equatable-only
/// makes the runtime fall back to Obj-C `-hash` on a boxed Swift value and log a
/// severe-performance warning on every layout pass.
public enum MarkerDecoration: Hashable {
    case codeBlock
    case quote(depth: Int)
    case thematicBreak
    case placeholder
}
