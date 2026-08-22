import Foundation

/// What a stretch of code is, semantically, so the theme can decide its colour.
///
/// Deliberately coarse. A dozen categories is what a reader actually uses to skim
/// code; a hundred is what a highlighter author enjoys writing.
public enum TokenKind: String, Sendable, Equatable, CaseIterable {
    case plain
    case keyword
    case type
    case string
    case number
    case comment
    case punctuation
    /// Attributes, annotations, decorators, preprocessor lines, YAML keys.
    case attribute
}

/// A token carries its text rather than a range into the source.
///
/// Concatenating every token's text reproduces the input exactly, which is
/// asserted by a test. That property is what lets the renderer append tokens one
/// after another with no offset arithmetic, and it removes the entire class of
/// bug where a highlighter's ranges drift out of step with the string it
/// highlighted.
public struct Token: Sendable, Equatable {
    public let kind: TokenKind
    public let text: String

    public init(kind: TokenKind, text: String) {
        self.kind = kind
        self.text = text
    }
}
