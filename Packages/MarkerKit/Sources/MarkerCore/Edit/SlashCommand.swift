import Foundation

/// Something you can insert by typing `/` in the editor.
///
/// The snippets live here rather than in the UI so their exact text is testable.
/// A table that comes out with the wrong number of pipes is not something to find
/// out about from a screenshot.
public struct SlashCommand: Sendable, Equatable, Identifiable {

    public var id: String { name }

    public let name: String
    public let detail: String
    /// SF Symbol shown beside the row.
    public let symbol: String
    /// Extra words that should match this command, beyond its name.
    public let keywords: [String]
    /// The text inserted. `‸` marks where the caret lands afterwards and is never
    /// part of the output.
    public let snippet: String
    /// Whether the snippet is a block, and so needs to start on a line of its own.
    public let isBlock: Bool

    public static let caretMarker: Character = "‸"

    public init(
        name: String,
        detail: String,
        symbol: String,
        keywords: [String] = [],
        snippet: String,
        isBlock: Bool = true
    ) {
        self.name = name
        self.detail = detail
        self.symbol = symbol
        self.keywords = keywords
        self.snippet = snippet
        self.isBlock = isBlock
    }
}

public extension SlashCommand {

    /// Ordered by how often a markdown document actually needs them.
    static let all: [SlashCommand] = [
        SlashCommand(
            name: "Table",
            detail: "Three columns with a header row",
            symbol: "tablecells",
            keywords: ["grid", "rows", "columns"],
            snippet: """
            | ‸Column | Column | Column |
            |---------|--------|--------|
            |         |        |        |
            |         |        |        |
            """
        ),
        SlashCommand(
            name: "Code block",
            detail: "A fenced block with a language",
            symbol: "chevron.left.forwardslash.chevron.right",
            keywords: ["fence", "snippet", "swift"],
            snippet: "```‸\n\n```"
        ),
        SlashCommand(
            name: "Flowchart",
            detail: "A Mermaid graph, rendered natively",
            symbol: "point.topleft.down.to.point.bottomright.curvepath",
            keywords: ["mermaid", "diagram", "graph"],
            snippet: """
            ```mermaid
            graph TD
                A[‸Start] --> B{Choice}
                B -->|yes| C[Do it]
                B -->|no| D[Stop]
            ```
            """
        ),
        SlashCommand(
            name: "Sequence diagram",
            detail: "A Mermaid sequence, rendered natively",
            symbol: "arrow.left.arrow.right",
            keywords: ["mermaid", "diagram", "messages"],
            snippet: """
            ```mermaid
            sequenceDiagram
                participant A as ‸Alice
                participant B as Bob
                A->>B: Hello
                B-->>A: Hello back
            ```
            """
        ),
        SlashCommand(
            name: "Math block",
            detail: "Display LaTeX, rendered natively",
            symbol: "function",
            keywords: ["latex", "equation", "formula"],
            snippet: "$$\n‸\n$$"
        ),
        SlashCommand(
            name: "Heading 1",
            detail: "A top level heading",
            symbol: "textformat.size.larger",
            keywords: ["h1", "title"],
            snippet: "# ‸"
        ),
        SlashCommand(
            name: "Heading 2",
            detail: "A section heading",
            symbol: "textformat.size",
            keywords: ["h2", "section"],
            snippet: "## ‸"
        ),
        SlashCommand(
            name: "Heading 3",
            detail: "A subsection heading",
            symbol: "textformat.size.smaller",
            keywords: ["h3"],
            snippet: "### ‸"
        ),
        SlashCommand(
            name: "Bullet list",
            detail: "An unordered list",
            symbol: "list.bullet",
            keywords: ["ul", "unordered", "items"],
            snippet: "- ‸\n- \n- "
        ),
        SlashCommand(
            name: "Numbered list",
            detail: "An ordered list",
            symbol: "list.number",
            keywords: ["ol", "ordered", "steps"],
            snippet: "1. ‸\n2. \n3. "
        ),
        SlashCommand(
            name: "Task list",
            detail: "Checkboxes you can tick",
            symbol: "checklist",
            keywords: ["todo", "checkbox", "checklist"],
            snippet: "- [ ] ‸\n- [ ] \n- [ ] "
        ),
        SlashCommand(
            name: "Quote",
            detail: "A block quote",
            symbol: "text.quote",
            keywords: ["blockquote", "cite"],
            snippet: "> ‸"
        ),
        SlashCommand(
            name: "Divider",
            detail: "A horizontal rule",
            symbol: "minus",
            keywords: ["rule", "hr", "separator", "break"],
            snippet: "---\n\n‸"
        ),
        SlashCommand(
            name: "Link",
            detail: "An inline link",
            symbol: "link",
            keywords: ["url", "href", "anchor"],
            snippet: "[‸](https://)",
            isBlock: false
        ),
        SlashCommand(
            name: "Image",
            detail: "An inline image",
            symbol: "photo",
            keywords: ["picture", "figure"],
            snippet: "![‸](path/to/image.png)",
            isBlock: false
        ),
        SlashCommand(
            name: "Inline code",
            detail: "Code inside a sentence",
            symbol: "curlybraces",
            keywords: ["backtick", "monospace"],
            snippet: "`‸`",
            isBlock: false
        ),
    ]

    /// Commands matching a query, best first.
    ///
    /// Prefix matches on the name rank above prefix matches on a keyword, which
    /// rank above matches anywhere. Anything else is dropped, because a menu that
    /// keeps showing everything is not filtering.
    static func matching(_ query: String) -> [SlashCommand] {
        let needle = query.lowercased().trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else { return all }

        func rank(_ command: SlashCommand) -> Int? {
            let name = command.name.lowercased()
            if name.hasPrefix(needle) { return 0 }
            if command.keywords.contains(where: { $0.hasPrefix(needle) }) { return 1 }
            if name.contains(needle) { return 2 }
            if command.keywords.contains(where: { $0.contains(needle) }) { return 3 }
            return nil
        }

        return all
            .compactMap { command in rank(command).map { (command, $0) } }
            // Stable within a rank: `all` is already in usefulness order.
            .sorted { $0.1 < $1.1 }
            .map(\.0)
    }
}

/// Turns a chosen command into an edit against the source.
public enum SlashCommandInsertion {

    public struct Result: Equatable {
        public let edit: TextEdit
        /// Where the caret should sit afterwards, in source bytes.
        public let caret: Int
    }

    /// Replaces the `/query` token with the command's snippet.
    ///
    /// A block command inserted partway through a line gets a blank line before it,
    /// because a table appended to the end of a sentence is not a table.
    public static func apply(
        _ command: SlashCommand,
        replacing token: Range<Int>,
        in source: MarkdownSource
    ) -> Result {
        let prefixOnLine = textBeforeOnLine(token.lowerBound, in: source)
        let needsBreak = command.isBlock && !prefixOnLine.trimmingCharacters(in: .whitespaces).isEmpty

        var body = command.snippet
        var caretOffset = body.firstIndex(of: SlashCommand.caretMarker)
            .map { body.distance(from: body.startIndex, to: $0) }
        if let index = body.firstIndex(of: SlashCommand.caretMarker) {
            body.remove(at: index)
        } else {
            caretOffset = body.count
        }

        let lead = needsBreak ? "\n\n" : ""
        let replacement = lead + body

        // The caret marker was counted in characters; the edit is in bytes.
        let caretPrefix = String(replacement.prefix((caretOffset ?? 0) + lead.count))
        return Result(
            edit: TextEdit(byteRange: token, replacement: replacement),
            caret: token.lowerBound + caretPrefix.utf8.count
        )
    }

    /// The text between the start of the line and `offset`.
    static func textBeforeOnLine(_ offset: Int, in source: MarkdownSource) -> String {
        let bytes = Array(source.text.utf8)
        guard offset <= bytes.count else { return "" }
        var start = offset
        while start > 0, bytes[start - 1] != 0x0A { start -= 1 }
        return String(bytes: bytes[start ..< offset], encoding: .utf8) ?? ""
    }

    /// Finds the `/query` token the caret sits in, or nil when the caret is not in
    /// one.
    ///
    /// A slash only opens the menu at the start of a line or after whitespace, so
    /// `and/or`, `http://` and a path like `src/main` never trigger it.
    public static func activeToken(at caret: Int, in source: MarkdownSource) -> Range<Int>? {
        let bytes = Array(source.text.utf8)
        guard caret <= bytes.count else { return nil }

        var start = caret
        while start > 0 {
            let byte = bytes[start - 1]
            if byte == 0x2F { start -= 1; break }          // the slash itself
            if byte == 0x0A || byte == 0x20 || byte == 0x09 { return nil }
            start -= 1
            if caret - start > 32 { return nil }           // no menu after a long word
        }
        guard start < caret, bytes[start] == 0x2F else { return nil }

        // What precedes the slash decides whether this is a command or just text.
        if start > 0 {
            let previous = bytes[start - 1]
            guard previous == 0x0A || previous == 0x20 || previous == 0x09 else { return nil }
        }
        return start ..< caret
    }

    /// The query text inside a token, without the leading slash.
    public static func query(for token: Range<Int>, in source: MarkdownSource) -> String {
        guard let text = source.slice(token) else { return "" }
        return String(text.dropFirst())
    }
}
