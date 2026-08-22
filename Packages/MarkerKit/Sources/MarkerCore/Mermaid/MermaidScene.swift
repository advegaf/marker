import CoreGraphics
import Foundation

/// What to draw, with no idea how to draw it.
///
/// The layout produces one of these and the renderer consumes it. Keeping the
/// boundary at plain geometry is what lets the whole engine be tested by asserting
/// on coordinates, which is a far better test than comparing pixels: a pixel diff
/// tells you something moved, a coordinate assertion tells you what.
public struct MermaidScene: Sendable, Equatable {

    public enum ShapeKind: Sendable, Equatable {
        case rectangle(cornerRadius: CGFloat)
        case diamond
        case ellipse
        case hexagon
        /// A rectangle with a doubled left and right edge.
        case subroutine
        case cylinder
        /// A participant's lifeline box in a sequence diagram.
        case note
    }

    public enum Stroke: Sendable, Equatable {
        case solid(width: CGFloat)
        case dashed(width: CGFloat, pattern: [CGFloat])
    }

    public struct Shape: Sendable, Equatable {
        public var kind: ShapeKind
        public var frame: CGRect
        public var stroke: Stroke
        public var filled: Bool

        public init(kind: ShapeKind, frame: CGRect, stroke: Stroke = .solid(width: 1.5), filled: Bool = true) {
            self.kind = kind
            self.frame = frame
            self.stroke = stroke
            self.filled = filled
        }
    }

    public struct Path: Sendable, Equatable {
        /// Already routed. The renderer joins them with straight segments.
        public var points: [CGPoint]
        public var stroke: Stroke
        public var hasArrowHead: Bool
        /// A hollow head, for the open arrows in sequence diagrams.
        public var isOpenHead: Bool
        /// An x instead of a head, for `-x` messages.
        public var isCrossHead: Bool

        public init(
            points: [CGPoint], stroke: Stroke = .solid(width: 1.5),
            hasArrowHead: Bool = true, isOpenHead: Bool = false, isCrossHead: Bool = false
        ) {
            self.points = points
            self.stroke = stroke
            self.hasArrowHead = hasArrowHead
            self.isOpenHead = isOpenHead
            self.isCrossHead = isCrossHead
        }
    }

    public enum TextRole: Sendable, Equatable {
        case nodeLabel
        case edgeLabel
        case participant
        case title
        case note
    }

    public struct Text: Sendable, Equatable {
        public var string: String
        /// The box the text is centred in.
        public var frame: CGRect
        public var role: TextRole

        public init(string: String, frame: CGRect, role: TextRole) {
            self.string = string
            self.frame = frame
            self.role = role
        }
    }

    public var size: CGSize
    public var shapes: [Shape]
    public var paths: [Path]
    public var texts: [Text]
    /// Boxes painted behind edge labels so a line does not run through the words.
    public var labelBackgrounds: [CGRect]

    public init(
        size: CGSize,
        shapes: [Shape] = [],
        paths: [Path] = [],
        texts: [Text] = [],
        labelBackgrounds: [CGRect] = []
    ) {
        self.size = size
        self.shapes = shapes
        self.paths = paths
        self.texts = texts
        self.labelBackgrounds = labelBackgrounds
    }
}

/// How the layout finds out how big a piece of text is.
///
/// Injected rather than imported so `MermaidCore` never needs AppKit and the tests
/// can supply a deterministic ruler, which keeps asserted coordinates stable across
/// machines and font versions.
public struct TextMeasure: Sendable {
    public let size: @Sendable (_ text: String, _ pointSize: CGFloat) -> CGSize

    public init(size: @escaping @Sendable (String, CGFloat) -> CGSize) {
        self.size = size
    }

    /// A rough ruler for tests: every glyph is 0.58 em wide, lines are 1.25 em tall.
    public static let deterministic = TextMeasure { text, pointSize in
        let lines = text.components(separatedBy: "\n")
        let widest = lines.map(\.count).max() ?? 0
        return CGSize(
            width: CGFloat(widest) * pointSize * 0.58,
            height: CGFloat(max(lines.count, 1)) * pointSize * 1.25
        )
    }
}

/// The sizes and spacings a diagram is laid out with.
public struct MermaidStyle: Sendable {
    public var fontSize: CGFloat
    public var edgeLabelFontSize: CGFloat
    public var nodePaddingX: CGFloat
    public var nodePaddingY: CGFloat
    public var minNodeWidth: CGFloat
    public var minNodeHeight: CGFloat
    /// Space between one rank and the next, along the flow direction.
    public var rankSpacing: CGFloat
    /// Space between siblings within a rank.
    public var nodeSpacing: CGFloat
    public var padding: CGFloat

    public init(fontSize: CGFloat = 14) {
        self.fontSize = fontSize
        self.edgeLabelFontSize = fontSize * 0.85
        self.nodePaddingX = fontSize * 1.35
        self.nodePaddingY = fontSize * 0.85
        self.minNodeWidth = fontSize * 3.4
        self.minNodeHeight = fontSize * 2.4
        self.rankSpacing = fontSize * 4.2
        self.nodeSpacing = fontSize * 2.0
        self.padding = fontSize * 1.5
    }
}
