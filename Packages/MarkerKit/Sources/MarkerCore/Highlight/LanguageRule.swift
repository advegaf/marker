import Foundation

/// How one language's surface syntax is recognised.
///
/// A table rather than a grammar. Highlighting is a reading aid, not a compiler
/// front end, and a table is small enough to read, fast enough to run on every
/// keystroke, and cannot hang on pathological input the way a backtracking regex
/// can.
public struct LanguageRule: Sendable {

    public enum Flavor: Sendable {
        /// Identifiers, numbers, strings, comments. Covers nearly everything.
        case code
        /// Angle-bracket markup: tags, attributes, entities.
        case markup
        /// Indentation and `key: value`, where the key is the thing worth colouring.
        case yaml
    }

    public var names: [String]
    public var flavor: Flavor
    public var keywords: Set<String>
    public var types: Set<String>
    public var literals: Set<String>
    public var lineComments: [String]
    public var blockComment: (open: String, close: String)?
    public var stringDelimiters: Set<Character>
    /// Languages where a run of three delimiters opens a multi-line string.
    public var tripleQuoted: Bool
    /// Languages where a capitalised identifier is conventionally a type.
    public var capitalisedIdentifiersAreTypes: Bool
    /// Prefix that marks an attribute, annotation or decorator: `@`, `#[`, `#`.
    public var attributePrefixes: [String]

    public init(
        names: [String],
        flavor: Flavor = .code,
        keywords: Set<String> = [],
        types: Set<String> = [],
        literals: Set<String> = [],
        lineComments: [String] = [],
        blockComment: (open: String, close: String)? = nil,
        stringDelimiters: Set<Character> = ["\"", "'"],
        tripleQuoted: Bool = false,
        capitalisedIdentifiersAreTypes: Bool = false,
        attributePrefixes: [String] = []
    ) {
        self.names = names
        self.flavor = flavor
        self.keywords = keywords
        self.types = types
        self.literals = literals
        self.lineComments = lineComments
        self.blockComment = blockComment
        self.stringDelimiters = stringDelimiters
        self.tripleQuoted = tripleQuoted
        self.capitalisedIdentifiersAreTypes = capitalisedIdentifiersAreTypes
        self.attributePrefixes = attributePrefixes
    }
}
