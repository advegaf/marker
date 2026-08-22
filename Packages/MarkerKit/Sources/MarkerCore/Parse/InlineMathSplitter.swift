import Foundation

/// Finds `$…$` spans inside a run of source text.
///
/// Works on the raw source rather than on cmark's `Text.string`, deliberately.
/// CommonMark unescapes a backslash before ASCII punctuation, and LaTeX is mostly
/// backslashes, so `x\_1` would arrive as `x_1` and render as the wrong formula.
/// The raw bytes are what the author typed.
public enum InlineMathSplitter {

    public struct Segment: Equatable {
        public let text: String
        public let isMath: Bool
        /// Offset of this segment from the start of the text it was split out of,
        /// in UTF-8 bytes, so the caller can turn it back into a source range.
        public let byteOffset: Int
        /// Byte length of the segment including its `$` delimiters, when math.
        public let byteLength: Int
    }

    /// Splits on inline math, or returns a single non-math segment.
    ///
    /// The delimiter rules exist to keep prices out. An opening `$` must be
    /// followed immediately by a non-space, a closing `$` must be preceded
    /// immediately by a non-space, and neither may straddle a line break. That
    /// leaves "it costs $5 and $10" alone, which the naive rule would turn into a
    /// formula reading "5 and ".
    public static func split(_ text: String) -> [Segment] {
        guard text.contains("$") else {
            return [Segment(text: text, isMath: false, byteOffset: 0, byteLength: text.utf8.count)]
        }

        let characters = Array(text)
        var segments: [Segment] = []
        var plain = ""
        var plainStart = 0
        var byteOffset = 0
        var index = 0

        func flushPlain() {
            guard !plain.isEmpty else { return }
            segments.append(Segment(
                text: plain, isMath: false,
                byteOffset: plainStart, byteLength: plain.utf8.count
            ))
            plain = ""
        }

        while index < characters.count {
            let character = characters[index]
            guard character == "$",
                  !isEscaped(characters, at: index),
                  let close = closingDelimiter(in: characters, openedAt: index) else {
                if plain.isEmpty { plainStart = byteOffset }
                plain.append(character)
                byteOffset += String(character).utf8.count
                index += 1
                continue
            }

            flushPlain()
            let latex = String(characters[(index + 1) ..< close])
            let whole = String(characters[index ... close])
            segments.append(Segment(
                text: latex, isMath: true,
                byteOffset: byteOffset, byteLength: whole.utf8.count
            ))
            byteOffset += whole.utf8.count
            index = close + 1
            plainStart = byteOffset
        }

        flushPlain()
        return segments
    }

    /// A `$` preceded by an odd number of backslashes was escaped by the author and
    /// is a literal dollar sign. Counting the run matters: `\\$` is an escaped
    /// backslash followed by a real delimiter.
    private static func isEscaped(_ characters: [Character], at index: Int) -> Bool {
        var backslashes = 0
        var position = index - 1
        while position >= 0, characters[position] == "\\" {
            backslashes += 1
            position -= 1
        }
        return backslashes % 2 == 1
    }

    private static func closingDelimiter(in characters: [Character], openedAt open: Int) -> Int? {
        let next = open + 1
        guard next < characters.count, !characters[next].isWhitespace else { return nil }

        var index = next
        while index < characters.count {
            let character = characters[index]
            // A formula does not span a paragraph, and refusing to cross a line
            // break keeps a stray `$` from swallowing the rest of the text.
            if character.isNewline { return nil }
            if character == "$", !characters[index - 1].isWhitespace,
               !isEscaped(characters, at: index) {
                return index > open + 1 ? index : nil
            }
            index += 1
        }
        return nil
    }
}
