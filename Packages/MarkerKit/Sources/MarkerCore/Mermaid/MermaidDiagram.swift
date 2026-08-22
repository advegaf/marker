import Foundation

/// The parsed shape of a Mermaid diagram, before any geometry.
///
/// Kept as plain values with no AppKit anywhere, so the whole engine, lexer
/// through layout, runs headless under `swift test` and its geometry can be
/// asserted on directly rather than compared as pixels.
public enum MermaidDiagram: Sendable, Equatable {
    case flowchart(Flowchart)
    case sequence(SequenceDiagram)
}

// MARK: - Flowchart

public struct Flowchart: Sendable, Equatable {

    public enum Direction: String, Sendable, Equatable {
        case topDown, bottomUp, leftRight, rightLeft

        /// Mermaid spells the same four directions several ways.
        public init?(keyword: String) {
            switch keyword.uppercased() {
            case "TD", "TB": self = .topDown
            case "BT": self = .bottomUp
            case "LR": self = .leftRight
            case "RL": self = .rightLeft
            default: return nil
            }
        }

        public var isVertical: Bool { self == .topDown || self == .bottomUp }
    }

    public enum NodeShape: Sendable, Equatable {
        case rectangle      // [text]
        case rounded        // (text)
        case stadium        // ([text])
        case diamond        // {text}
        case circle         // ((text))
        case hexagon        // {{text}}
        case subroutine     // [[text]]
        case cylinder       // [(text)]
    }

    public enum EdgeStyle: Sendable, Equatable {
        case solid
        case dotted
        case thick
    }

    public struct Node: Sendable, Equatable {
        public let id: String
        public var label: String
        public var shape: NodeShape

        public init(id: String, label: String, shape: NodeShape) {
            self.id = id
            self.label = label
            self.shape = shape
        }
    }

    public struct Edge: Sendable, Equatable {
        public let from: String
        public let to: String
        public var label: String?
        public var style: EdgeStyle
        /// `---` and friends draw a line with no head.
        public var hasArrowHead: Bool

        public init(
            from: String, to: String, label: String? = nil,
            style: EdgeStyle = .solid, hasArrowHead: Bool = true
        ) {
            self.from = from
            self.to = to
            self.label = label
            self.style = style
            self.hasArrowHead = hasArrowHead
        }
    }

    public var direction: Direction
    /// Insertion ordered, because layout ties are broken by declaration order and a
    /// dictionary would make the output depend on hashing.
    public var nodes: [Node]
    public var edges: [Edge]

    public init(direction: Direction, nodes: [Node], edges: [Edge]) {
        self.direction = direction
        self.nodes = nodes
        self.edges = edges
    }

    public func node(id: String) -> Node? { nodes.first { $0.id == id } }
}

// MARK: - Sequence

public struct SequenceDiagram: Sendable, Equatable {

    public enum ArrowStyle: Sendable, Equatable {
        case solid          // ->>
        case dotted         // -->>
        case solidOpen      // ->
        case dottedOpen     // -->
        case cross          // -x
    }

    public struct Participant: Sendable, Equatable {
        public let id: String
        public var label: String
        /// `actor` draws a stick figure instead of a box.
        public var isActor: Bool

        public init(id: String, label: String, isActor: Bool = false) {
            self.id = id
            self.label = label
            self.isActor = isActor
        }
    }

    public struct Message: Sendable, Equatable {
        public let from: String
        public let to: String
        public var text: String
        public var style: ArrowStyle
        /// `activate`/`deactivate` and `+`/`-` suffixes.
        public var activates: Bool
        public var deactivates: Bool

        public init(
            from: String, to: String, text: String, style: ArrowStyle,
            activates: Bool = false, deactivates: Bool = false
        ) {
            self.from = from
            self.to = to
            self.text = text
            self.style = style
            self.activates = activates
            self.deactivates = deactivates
        }
    }

    public struct Note: Sendable, Equatable {
        public enum Placement: Sendable, Equatable {
            case leftOf(String), rightOf(String), over([String])
        }
        public var placement: Placement
        public var text: String
        /// Index in the message list this note follows.
        public var afterMessage: Int

        public init(placement: Placement, text: String, afterMessage: Int) {
            self.placement = placement
            self.text = text
            self.afterMessage = afterMessage
        }
    }

    public var title: String?
    public var participants: [Participant]
    public var messages: [Message]
    public var notes: [Note]

    public init(
        title: String? = nil,
        participants: [Participant],
        messages: [Message],
        notes: [Note] = []
    ) {
        self.title = title
        self.participants = participants
        self.messages = messages
        self.notes = notes
    }
}
