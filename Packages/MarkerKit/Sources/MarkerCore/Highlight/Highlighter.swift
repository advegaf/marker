import Foundation

/// A hand-written scanner, one pass, no regular expressions.
///
/// Highlightr would have meant embedding a JS engine plus most of a megabyte
/// of highlight.js, and tree-sitter is heavier still. READMEs use a narrow set of
/// languages, and the product sells a small binary. This is a few hundred lines
/// that covers them and cannot backtrack.
public enum Highlighter {

    /// Splits code into tokens. Concatenating their text reproduces `code` exactly.
    /// An unknown language returns a single plain token, so a fence in a language we
    /// do not know still renders as code rather than disappearing.
    public static func tokenize(_ code: String, language: String?) -> [Token] {
        guard let rule = LanguageRule.named(language) else {
            return code.isEmpty ? [] : [Token(kind: .plain, text: code)]
        }
        switch rule.flavor {
        case .code:
            var scanner = Scanner(code: code, rule: rule)
            return scanner.scan()
        case .markup:
            var scanner = MarkupScanner(code: code)
            return scanner.scan()
        case .yaml:
            var scanner = YAMLScanner(code: code)
            return scanner.scan()
        }
    }

    /// True when the language has a rule, used to decide whether a fence gets a
    /// language badge in the rendered output.
    public static func supports(_ language: String?) -> Bool {
        LanguageRule.named(language) != nil
    }
}

// MARK: - Code

private struct Scanner {
    let characters: [Character]
    let rule: LanguageRule
    var index = 0
    var tokens: [Token] = []
    var pending = ""

    init(code: String, rule: LanguageRule) {
        self.characters = Array(code)
        self.rule = rule
    }

    mutating func scan() -> [Token] {
        while index < characters.count {
            if scanComment() { continue }
            if scanString() { continue }
            if scanAttribute() { continue }
            if scanNumber() { continue }
            if scanIdentifier() { continue }
            scanPunctuationOrPlain()
        }
        flush()
        return tokens
    }

    // MARK: Emission

    mutating func flush() {
        guard !pending.isEmpty else { return }
        tokens.append(Token(kind: .plain, text: pending))
        pending = ""
    }

    mutating func emit(_ kind: TokenKind, _ text: String) {
        guard !text.isEmpty else { return }
        flush()
        tokens.append(Token(kind: kind, text: text))
    }

    // MARK: Lookahead

    func peek(_ offset: Int = 0) -> Character? {
        let position = index + offset
        return position < characters.count ? characters[position] : nil
    }

    func matches(_ text: String) -> Bool {
        let needle = Array(text)
        guard index + needle.count <= characters.count else { return false }
        for (offset, character) in needle.enumerated()
        where characters[index + offset] != character { return false }
        return true
    }

    mutating func take(_ count: Int) -> String {
        let end = min(index + count, characters.count)
        let text = String(characters[index ..< end])
        index = end
        return text
    }

    // MARK: Rules

    mutating func scanComment() -> Bool {
        for marker in rule.lineComments where matches(marker) {
            var text = take(marker.count)
            while let character = peek(), character != "\n" { text.append(take(1)) }
            emit(.comment, text)
            return true
        }
        guard let block = rule.blockComment, matches(block.open) else { return false }
        var text = take(block.open.count)
        while index < characters.count, !matches(block.close) { text.append(take(1)) }
        text += take(block.close.count)
        emit(.comment, text)
        return true
    }

    mutating func scanString() -> Bool {
        guard let quote = peek(), rule.stringDelimiters.contains(quote) else { return false }

        if rule.tripleQuoted, peek(1) == quote, peek(2) == quote {
            let fence = String(repeating: String(quote), count: 3)
            var text = take(3)
            while index < characters.count, !matches(fence) {
                // A backslash escapes whatever follows, the closing fence included.
                if peek() == "\\" { text += take(2) } else { text += take(1) }
            }
            text += take(3)
            emit(.string, text)
            return true
        }

        var text = take(1)
        while let character = peek() {
            if character == "\\" { text += take(2); continue }
            // An unterminated string ends at the line break rather than eating the
            // rest of the file, which is what a reader expects while typing one.
            if character == "\n" { break }
            text += take(1)
            if character == quote { break }
        }
        emit(.string, text)
        return true
    }

    mutating func scanAttribute() -> Bool {
        for prefix in rule.attributePrefixes where matches(prefix) {
            var text = take(prefix.count)
            while let character = peek(), character.isLetter || character.isNumber
                || character == "_" || character == "." || character == ":" {
                text += take(1)
            }
            // A bare prefix with nothing after it is punctuation, not an attribute.
            guard text.count > prefix.count else { pending += text; return true }
            emit(.attribute, text)
            return true
        }
        return false
    }

    mutating func scanNumber() -> Bool {
        guard let character = peek(), character.isNumber else { return false }
        var text = ""
        while let character = peek(), character.isHexDigit || character == "."
            || character == "_" || character == "x" || character == "X"
            || character == "o" || character == "b" {
            text += take(1)
        }
        emit(.number, text)
        return true
    }

    mutating func scanIdentifier() -> Bool {
        guard let character = peek(), character.isLetter || character == "_" else { return false }
        var text = ""
        while let character = peek(), character.isLetter || character.isNumber || character == "_" {
            text += take(1)
        }
        if rule.keywords.contains(text) {
            emit(.keyword, text)
        } else if rule.literals.contains(text) {
            emit(.number, text)
        } else if rule.types.contains(text) {
            emit(.type, text)
        } else if rule.capitalisedIdentifiersAreTypes, let first = text.first, first.isUppercase {
            emit(.type, text)
        } else {
            pending += text
        }
        return true
    }

    mutating func scanPunctuationOrPlain() {
        let character = take(1)
        if let scalar = character.unicodeScalars.first,
           CharacterSet.punctuationCharacters.contains(scalar)
            || CharacterSet.symbols.contains(scalar) {
            emit(.punctuation, character)
        } else {
            pending += character
        }
    }
}

// MARK: - Markup

/// Angle-bracket markup. Tag names and attribute names are the load bearing parts
/// when skimming HTML, so those get the colour, and text content stays plain.
private struct MarkupScanner {
    let characters: [Character]
    var index = 0
    var tokens: [Token] = []

    init(code: String) { self.characters = Array(code) }

    mutating func scan() -> [Token] {
        while index < characters.count {
            if characters[index] == "<" {
                scanTag()
            } else {
                var text = ""
                while index < characters.count, characters[index] != "<" {
                    text.append(characters[index]); index += 1
                }
                append(.plain, text)
            }
        }
        return tokens
    }

    mutating func scanTag() {
        // Comments and doctype run to their own terminator, not to the next `>`.
        if matches("<!--") {
            var text = ""
            while index < characters.count, !matches("-->") {
                text.append(characters[index]); index += 1
            }
            text += consume(3)
            append(.comment, text)
            return
        }

        append(.punctuation, consume(1))
        var name = ""
        if index < characters.count, characters[index] == "/" { name += consume(1) }
        while index < characters.count,
              characters[index].isLetter || characters[index].isNumber
                || characters[index] == "-" || characters[index] == "!" {
            name.append(characters[index]); index += 1
        }
        append(.keyword, name)

        while index < characters.count, characters[index] != ">" {
            let character = characters[index]
            if character == "\"" || character == "'" {
                var text = consume(1)
                while index < characters.count, characters[index] != character {
                    text.append(characters[index]); index += 1
                }
                text += consume(1)
                append(.string, text)
            } else if character.isLetter {
                var attribute = ""
                while index < characters.count,
                      characters[index].isLetter || characters[index].isNumber
                        || characters[index] == "-" || characters[index] == ":" {
                    attribute.append(characters[index]); index += 1
                }
                append(.attribute, attribute)
            } else {
                append(.plain, consume(1))
            }
        }
        if index < characters.count { append(.punctuation, consume(1)) }
    }

    func matches(_ text: String) -> Bool {
        let needle = Array(text)
        guard index + needle.count <= characters.count else { return false }
        for (offset, character) in needle.enumerated()
        where characters[index + offset] != character { return false }
        return true
    }

    mutating func consume(_ count: Int) -> String {
        let end = min(index + count, characters.count)
        let text = String(characters[index ..< end])
        index = end
        return text
    }

    mutating func append(_ kind: TokenKind, _ text: String) {
        guard !text.isEmpty else { return }
        if let last = tokens.last, last.kind == kind {
            tokens[tokens.count - 1] = Token(kind: kind, text: last.text + text)
        } else {
            tokens.append(Token(kind: kind, text: text))
        }
    }
}

// MARK: - YAML

/// YAML is not reformatted, only coloured. Reformatting it safely means a real
/// parser with anchors, aliases, flow style and multi-line scalars, and getting
/// that wrong rewrites someone's config. Colour is the useful half.
private struct YAMLScanner {
    let code: String
    var tokens: [Token] = []

    init(code: String) { self.code = code }

    mutating func scan() -> [Token] {
        let lines = code.components(separatedBy: "\n")
        for (index, line) in lines.enumerated() {
            scan(line: line)
            if index < lines.count - 1 { append(.plain, "\n") }
        }
        return tokens
    }

    mutating func scan(line: String) {
        let indentation = String(line.prefix { $0 == " " || $0 == "\t" })
        append(.plain, indentation)
        var rest = String(line.dropFirst(indentation.count))
        guard !rest.isEmpty else { return }

        if rest.hasPrefix("#") {
            append(.comment, rest)
            return
        }
        if rest.hasPrefix("- ") || rest == "-" {
            append(.punctuation, String(rest.prefix(rest == "-" ? 1 : 2)))
            rest = String(rest.dropFirst(rest == "-" ? 1 : 2))
        }
        // `key:` is the thing worth finding when skimming a config file.
        if let colon = rest.firstIndex(of: ":"),
           !rest.hasPrefix("\""), !rest.hasPrefix("'") {
            append(.attribute, String(rest[rest.startIndex ..< colon]))
            append(.punctuation, ":")
            rest = String(rest[rest.index(after: colon)...])
        }
        guard !rest.isEmpty else { return }

        if let hash = rest.range(of: " #") {
            scanValue(String(rest[rest.startIndex ..< hash.lowerBound]))
            append(.comment, String(rest[hash.lowerBound...]))
        } else {
            scanValue(rest)
        }
    }

    mutating func scanValue(_ value: String) {
        // Leading and trailing whitespace are both emitted, not just leading. Losing
        // the trailing run breaks the round trip, and in YAML whitespace is
        // structural, so a scanner that eats any of it cannot be trusted near a file
        // someone has to keep working.
        let leading = String(value.prefix { $0 == " " || $0 == "\t" })
        let trailing = String(value.reversed().prefix { $0 == " " || $0 == "\t" }.reversed())
        let trimmed = value.dropFirst(leading.count).dropLast(trailing.count)
        append(.plain, leading)
        guard !trimmed.isEmpty else { append(.plain, trailing); return }
        defer { append(.plain, trailing) }

        let text = String(trimmed)
        if text.hasPrefix("\"") || text.hasPrefix("'") {
            append(.string, text)
        } else if ["true", "false", "null", "yes", "no", "~"].contains(text.lowercased()) {
            append(.keyword, text)
        } else if Double(text) != nil {
            append(.number, text)
        } else {
            append(.plain, text)
        }
    }

    mutating func append(_ kind: TokenKind, _ text: String) {
        guard !text.isEmpty else { return }
        if let last = tokens.last, last.kind == kind {
            tokens[tokens.count - 1] = Token(kind: kind, text: last.text + text)
        } else {
            tokens.append(Token(kind: kind, text: text))
        }
    }
}
