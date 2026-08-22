import Foundation

public struct BlockID: Hashable, Sendable {
    public let value: Int
    public init(_ value: Int) { self.value = value }
}

public struct RunID: Hashable, Sendable {
    public let value: Int
    public init(_ value: Int) { self.value = value }
}

/// How much to trust a run's source range.
///
/// cmark computes inline positions against each block's reconstructed content
/// buffer, so content that was dedented on the way in (list continuations, block
/// quotes, lazy continuation lines) can report a column short by the stripped
/// prefix. Rather than assume, every run is checked against the source at lowering
/// time and labelled with the result.
public enum MapConfidence: Sendable, Equatable {
    /// The source slice matched the node's own literal exactly.
    case exact
    /// The literal was found nearby and the range was corrected.
    case recovered
}

public struct InlineStyle: OptionSet, Sendable, Hashable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let emphasis      = InlineStyle(rawValue: 1 << 0)
    public static let strong        = InlineStyle(rawValue: 1 << 1)
    public static let strikethrough = InlineStyle(rawValue: 1 << 2)
    public static let code          = InlineStyle(rawValue: 1 << 3)
    /// The run's text is LaTeX, not prose, and renders as a formula.
    public static let math          = InlineStyle(rawValue: 1 << 4)
}

/// One stretch of visible text with uniform styling.
///
/// `sourceRange` covers the bytes that produce the *visible* text, with
/// delimiters excluded. That is what makes typing at the end of a link's display
/// text land inside the brackets instead of after the URL, with no special case.
public struct InlineRun: Sendable, Equatable {
    public var id: RunID
    public var sourceRange: Range<Int>
    public var text: String
    public var style: InlineStyle
    public var linkURL: String?
    public var confidence: MapConfidence

    /// UTF-16 units this run contributes to the rendered string, which is the
    /// unit AppKit counts in.
    public var renderLength: Int { text.utf16.count }

    public init(
        id: RunID,
        sourceRange: Range<Int>,
        text: String,
        style: InlineStyle = [],
        linkURL: String? = nil,
        confidence: MapConfidence = .exact
    ) {
        self.id = id
        self.sourceRange = sourceRange
        self.text = text
        self.style = style
        self.linkURL = linkURL
        self.confidence = confidence
    }
}

/// Where a block sits inside nested lists and quotes.
public struct BlockContext: Sendable, Equatable {
    public var listDepth: Int
    public var quoteDepth: Int
    /// Set for ordered list items; nil for bullets and for anything not a list item.
    public var ordinal: Int?
    /// Set for task list items.
    public var checked: Bool?
    public var isListItemStart: Bool

    public static let none = BlockContext(
        listDepth: 0, quoteDepth: 0, ordinal: nil, checked: nil, isListItemStart: false
    )

    public init(
        listDepth: Int, quoteDepth: Int, ordinal: Int?, checked: Bool?, isListItemStart: Bool
    ) {
        self.listDepth = listDepth
        self.quoteDepth = quoteDepth
        self.ordinal = ordinal
        self.checked = checked
        self.isListItemStart = isListItemStart
    }
}

public enum BlockKind: Sendable, Equatable {
    case paragraph
    case heading(level: Int)
    case codeFence(language: String?, code: String)
    /// A ```mermaid fence, split out because it renders as a diagram rather than code.
    case mermaid(source: String)
    /// A $$...$$ block. Split out at lowering time rather than left as a paragraph,
    /// because cmark treats LaTeX backslash escapes as markdown escapes and eats them.
    case displayMath(latex: String)
    case thematicBreak
    case table(TableModel)
    case html(String)
    /// A block whose source map could not be trusted. Still renders, but edits in
    /// source-reveal mode, so it cannot be corrupted.
    case opaque(String)
}

public struct BlockNode: Sendable, Equatable {
    public var id: BlockID
    public var kind: BlockKind
    public var sourceRange: Range<Int>
    public var context: BlockContext
    public var runs: [InlineRun]

    public init(
        id: BlockID,
        kind: BlockKind,
        sourceRange: Range<Int>,
        context: BlockContext = .none,
        runs: [InlineRun] = []
    ) {
        self.id = id
        self.kind = kind
        self.sourceRange = sourceRange
        self.context = context
        self.runs = runs
    }

    /// Stable across re-renders, so an untouched table keeps its live view instead
    /// of being torn down whenever something else in the document changes.
    public var identityHash: Int {
        var hasher = Hasher()
        hasher.combine(kindTag)
        hasher.combine(runs.map(\.text).joined())
        hasher.combine(context.listDepth)
        hasher.combine(context.quoteDepth)
        return hasher.finalize()
    }

    private var kindTag: String {
        switch kind {
        case .paragraph: return "p"
        case .heading(let level): return "h\(level)"
        case .codeFence(let language, let code): return "code:\(language ?? ""):\(code)"
        case .mermaid(let source): return "mermaid:\(source)"
        case .displayMath(let latex): return "math:\(latex)"
        case .thematicBreak: return "hr"
        case .table(let model): return "table:\(model.rows.count)x\(model.columns.count)"
        case .html(let raw): return "html:\(raw)"
        case .opaque(let raw): return "opaque:\(raw)"
        }
    }
}
