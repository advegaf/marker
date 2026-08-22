import Foundation

/// Re-indents JSON without reordering it.
///
/// `JSONSerialization` would be less code, but it parses into a dictionary and
/// loses key order, so a minified config comes back alphabetised and unreadable
/// against the original. This is a structural pass instead: it only ever changes
/// whitespace between tokens.
///
/// Invalid JSON is returned unchanged. A viewer that mangles a file it could not
/// understand is worse than one that shows it as it is.
public enum JSONPrettyPrinter {

    public static func prettyPrinted(_ json: String, indent: String = "  ") -> String {
        // Prose has balanced brackets too, in the sense of having none, and would
        // otherwise come back with every space stripped out of it. Reformatting is
        // only ever applied to something that is actually a JSON container.
        let trimmed = json.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("{") || trimmed.hasPrefix("[") else { return json }

        var output = ""
        var depth = 0
        var characters = Array(json)
        var index = 0
        var sawContent = false

        func newline(_ level: Int) {
            output.append("\n")
            output.append(String(repeating: indent, count: max(level, 0)))
        }

        while index < characters.count {
            let character = characters[index]

            switch character {
            case "\"":
                // Strings pass through verbatim, escapes included, so nothing inside
                // one is ever mistaken for structure.
                var text = String(character)
                index += 1
                while index < characters.count {
                    let next = characters[index]
                    text.append(next)
                    index += 1
                    if next == "\\", index < characters.count {
                        text.append(characters[index]); index += 1
                        continue
                    }
                    if next == "\"" { break }
                }
                output += text
                sawContent = true

            case "{", "[":
                output.append(character)
                depth += 1
                index += 1
                // An empty container stays on one line rather than becoming three.
                var lookahead = index
                while lookahead < characters.count, characters[lookahead].isWhitespace { lookahead += 1 }
                if lookahead < characters.count,
                   characters[lookahead] == (character == "{" ? "}" : "]") {
                    index = lookahead
                    depth -= 1
                    output.append(characters[index])
                    index += 1
                } else {
                    newline(depth)
                }
                sawContent = true

            case "}", "]":
                depth -= 1
                newline(depth)
                output.append(character)
                index += 1

            case ",":
                output.append(character)
                index += 1
                newline(depth)

            case ":":
                output.append(": ")
                index += 1

            case " ", "\t", "\n", "\r":
                index += 1

            default:
                output.append(character)
                index += 1
                sawContent = true
            }
        }

        guard sawContent, depth == 0, isBalanced(json) else { return json }
        return output
    }

    /// A cheap structural check. The printer only moves whitespace, so the only way
    /// it can do harm is on input that was never valid; refusing those is enough.
    private static func isBalanced(_ json: String) -> Bool {
        var stack: [Character] = []
        var inString = false
        var escaping = false
        for character in json {
            if escaping { escaping = false; continue }
            if inString {
                if character == "\\" { escaping = true }
                if character == "\"" { inString = false }
                continue
            }
            switch character {
            case "\"": inString = true
            case "{", "[": stack.append(character)
            case "}":
                guard stack.popLast() == "{" else { return false }
            case "]":
                guard stack.popLast() == "[" else { return false }
            default: break
            }
        }
        return stack.isEmpty && !inString
    }
}
