import Foundation

/// The languages Marker highlights.
///
/// Chosen by what actually appears in READMEs and documentation, not by what is
/// popular in general. Adding one is a table entry, not code.
public extension LanguageRule {

    static func named(_ language: String?) -> LanguageRule? {
        guard let language, !language.isEmpty else { return nil }
        let key = language.lowercased().trimmingCharacters(in: .whitespaces)
        return index[key]
    }

    static let all: [LanguageRule] = [
        swift, javascript, python, rust, go, c, java, ruby, shell, sql, css, markup, yaml, json,
    ]

    private static let index: [String: LanguageRule] = {
        var table: [String: LanguageRule] = [:]
        for rule in all {
            for name in rule.names { table[name] = rule }
        }
        return table
    }()

    // MARK: Definitions

    static let swift = LanguageRule(
        names: ["swift"],
        keywords: [
            "actor", "any", "as", "associatedtype", "async", "await", "break", "case", "catch",
            "class", "consuming", "continue", "default", "defer", "deinit", "didSet", "do", "else",
            "enum", "extension", "fallthrough", "fileprivate", "final", "for", "func", "get",
            "guard", "if", "import", "in", "indirect", "init", "inout", "internal", "is", "lazy",
            "let", "mutating", "nonisolated", "open", "operator", "override", "package",
            "private", "protocol", "public", "repeat", "required", "rethrows", "return", "self",
            "set", "some", "static", "struct", "subscript", "super", "switch", "throw", "throws",
            "try", "typealias", "var", "weak", "where", "while", "willSet",
        ],
        literals: ["true", "false", "nil"],
        lineComments: ["//"],
        blockComment: ("/*", "*/"),
        stringDelimiters: ["\""],
        tripleQuoted: true,
        capitalisedIdentifiersAreTypes: true,
        attributePrefixes: ["@"]
    )

    static let javascript = LanguageRule(
        names: ["javascript", "js", "jsx", "typescript", "ts", "tsx", "node"],
        keywords: [
            "as", "async", "await", "break", "case", "catch", "class", "const", "continue",
            "debugger", "default", "delete", "do", "else", "enum", "export", "extends", "finally",
            "for", "from", "function", "get", "if", "implements", "import", "in", "instanceof",
            "interface", "let", "new", "of", "private", "protected", "public", "readonly",
            "return", "satisfies", "set", "static", "super", "switch", "this", "throw", "try",
            "type", "typeof", "var", "void", "while", "yield",
        ],
        types: ["string", "number", "boolean", "any", "unknown", "never", "object", "symbol"],
        literals: ["true", "false", "null", "undefined", "NaN"],
        lineComments: ["//"],
        blockComment: ("/*", "*/"),
        stringDelimiters: ["\"", "'", "`"],
        capitalisedIdentifiersAreTypes: true,
        attributePrefixes: ["@"]
    )

    static let python = LanguageRule(
        names: ["python", "py", "python3"],
        keywords: [
            "and", "as", "assert", "async", "await", "break", "class", "continue", "def", "del",
            "elif", "else", "except", "finally", "for", "from", "global", "if", "import", "in",
            "is", "lambda", "match", "nonlocal", "not", "or", "pass", "raise", "return", "try",
            "while", "with", "yield",
        ],
        types: ["int", "str", "float", "bool", "bytes", "list", "dict", "set", "tuple"],
        literals: ["True", "False", "None"],
        lineComments: ["#"],
        stringDelimiters: ["\"", "'"],
        tripleQuoted: true,
        capitalisedIdentifiersAreTypes: true,
        attributePrefixes: ["@"]
    )

    static let rust = LanguageRule(
        names: ["rust", "rs"],
        keywords: [
            "as", "async", "await", "break", "const", "continue", "crate", "dyn", "else", "enum",
            "extern", "fn", "for", "if", "impl", "in", "let", "loop", "match", "mod", "move",
            "mut", "pub", "ref", "return", "self", "static", "struct", "super", "trait", "type",
            "unsafe", "use", "where", "while",
        ],
        types: [
            "bool", "char", "f32", "f64", "i8", "i16", "i32", "i64", "i128", "isize", "str",
            "u8", "u16", "u32", "u64", "u128", "usize",
        ],
        literals: ["true", "false", "None", "Some", "Ok", "Err"],
        lineComments: ["//"],
        blockComment: ("/*", "*/"),
        stringDelimiters: ["\"", "'"],
        capitalisedIdentifiersAreTypes: true,
        attributePrefixes: ["#["]
    )

    static let go = LanguageRule(
        names: ["go", "golang"],
        keywords: [
            "break", "case", "chan", "const", "continue", "default", "defer", "else",
            "fallthrough", "for", "func", "go", "goto", "if", "import", "interface", "map",
            "package", "range", "return", "select", "struct", "switch", "type", "var",
        ],
        types: [
            "bool", "byte", "complex64", "complex128", "error", "float32", "float64", "int",
            "int8", "int16", "int32", "int64", "rune", "string", "uint", "uint8", "uint16",
            "uint32", "uint64", "uintptr",
        ],
        literals: ["true", "false", "nil", "iota"],
        lineComments: ["//"],
        blockComment: ("/*", "*/"),
        stringDelimiters: ["\"", "`", "'"]
    )

    static let c = LanguageRule(
        names: ["c", "cpp", "c++", "objc", "objective-c", "h", "hpp", "cc"],
        keywords: [
            "auto", "break", "case", "class", "const", "constexpr", "continue", "default",
            "delete", "do", "else", "enum", "extern", "for", "goto", "if", "inline", "namespace",
            "new", "nullptr", "operator", "private", "protected", "public", "return", "sizeof",
            "static", "struct", "switch", "template", "this", "typedef", "typename", "union",
            "using", "virtual", "volatile", "while",
        ],
        types: [
            "bool", "char", "double", "float", "int", "long", "short", "signed", "size_t",
            "unsigned", "void", "uint8_t", "uint16_t", "uint32_t", "uint64_t",
        ],
        literals: ["true", "false", "NULL"],
        lineComments: ["//"],
        blockComment: ("/*", "*/"),
        stringDelimiters: ["\"", "'"],
        capitalisedIdentifiersAreTypes: true,
        attributePrefixes: ["#"]
    )

    static let java = LanguageRule(
        names: ["java", "kotlin", "kt", "scala", "groovy"],
        keywords: [
            "abstract", "as", "break", "by", "case", "catch", "class", "companion", "const",
            "continue", "data", "do", "else", "enum", "extends", "final", "finally", "for", "fun",
            "if", "implements", "import", "in", "interface", "internal", "is", "lateinit", "new",
            "object", "open", "override", "package", "private", "protected", "public", "return",
            "sealed", "static", "super", "suspend", "switch", "this", "throw", "throws", "try",
            "val", "var", "when", "while",
        ],
        types: [
            "Boolean", "Byte", "Char", "Double", "Float", "Int", "Long", "Short", "String",
            "boolean", "byte", "char", "double", "float", "int", "long", "short", "void",
        ],
        literals: ["true", "false", "null"],
        lineComments: ["//"],
        blockComment: ("/*", "*/"),
        stringDelimiters: ["\"", "'"],
        tripleQuoted: true,
        capitalisedIdentifiersAreTypes: true,
        attributePrefixes: ["@"]
    )

    static let ruby = LanguageRule(
        names: ["ruby", "rb"],
        keywords: [
            "alias", "begin", "break", "case", "class", "def", "defined?", "do", "else", "elsif",
            "end", "ensure", "for", "if", "in", "module", "next", "raise", "redo", "require",
            "require_relative", "rescue", "retry", "return", "self", "super", "then", "unless",
            "until", "when", "while", "yield",
        ],
        literals: ["true", "false", "nil"],
        lineComments: ["#"],
        stringDelimiters: ["\"", "'"],
        capitalisedIdentifiersAreTypes: true,
        attributePrefixes: ["@", "$"]
    )

    static let shell = LanguageRule(
        names: ["shell", "sh", "bash", "zsh", "console", "shell-session", "fish"],
        keywords: [
            "case", "do", "done", "elif", "else", "esac", "exit", "export", "fi", "for",
            "function", "if", "in", "local", "readonly", "return", "set", "shift", "source",
            "then", "unset", "until", "while",
        ],
        types: ["cat", "cd", "cp", "echo", "grep", "ls", "mkdir", "mv", "rm", "sed", "awk"],
        lineComments: ["#"],
        stringDelimiters: ["\"", "'"],
        attributePrefixes: ["$"]
    )

    static let sql = LanguageRule(
        names: ["sql", "postgres", "postgresql", "mysql", "sqlite"],
        keywords: [
            "ALTER", "AND", "AS", "ASC", "BY", "CREATE", "DELETE", "DESC", "DISTINCT", "DROP",
            "EXISTS", "FROM", "GROUP", "HAVING", "IN", "INDEX", "INNER", "INSERT", "INTO", "JOIN",
            "LEFT", "LIMIT", "NOT", "ON", "OR", "ORDER", "OUTER", "PRIMARY", "SELECT", "SET",
            "TABLE", "UNION", "UPDATE", "VALUES", "WHERE", "WITH",
            "alter", "and", "as", "asc", "by", "create", "delete", "desc", "distinct", "drop",
            "exists", "from", "group", "having", "in", "index", "inner", "insert", "into", "join",
            "left", "limit", "not", "on", "or", "order", "outer", "primary", "select", "set",
            "table", "union", "update", "values", "where", "with",
        ],
        types: ["BOOLEAN", "DATE", "INT", "INTEGER", "TEXT", "TIMESTAMP", "VARCHAR"],
        literals: ["NULL", "TRUE", "FALSE", "null", "true", "false"],
        lineComments: ["--"],
        blockComment: ("/*", "*/"),
        stringDelimiters: ["'", "\""]
    )

    static let css = LanguageRule(
        names: ["css", "scss", "sass", "less"],
        keywords: [
            "and", "from", "important", "media", "not", "supports", "to",
        ],
        lineComments: ["//"],
        blockComment: ("/*", "*/"),
        stringDelimiters: ["\"", "'"],
        attributePrefixes: ["@", "--", "$"]
    )

    static let markup = LanguageRule(names: ["html", "xml", "svg", "vue", "xhtml"], flavor: .markup)

    static let yaml = LanguageRule(names: ["yaml", "yml"], flavor: .yaml)

    static let json = LanguageRule(
        names: ["json", "jsonc", "json5"],
        keywords: [],
        literals: ["true", "false", "null"],
        lineComments: ["//"],
        stringDelimiters: ["\""]
    )
}
