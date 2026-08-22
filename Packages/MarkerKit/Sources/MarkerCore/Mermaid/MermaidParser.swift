import Foundation

/// Parses the subset of Mermaid that Marker renders.
///
/// Line oriented rather than a general grammar, because Mermaid is line oriented
/// and a hand-written parser can say precisely which line it did not understand.
/// Anything it cannot read raises `MermaidParseError`, and the renderer shows the
/// fence as code with the failing line named, which is more use than an empty box.
public enum MermaidParser {

    public static func parse(_ source: String) throws -> MermaidDiagram {
        let lines = source
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }

        guard let headerIndex = lines.firstIndex(where: { !$0.isEmpty && !$0.hasPrefix("%%") }) else {
            throw MermaidParseError(line: 1, message: "the diagram is empty")
        }

        let header = lines[headerIndex]
        let body = Array(lines[(headerIndex + 1)...])
        let keyword = header.split(separator: " ", maxSplits: 1).first.map(String.init) ?? header

        switch keyword.lowercased() {
        case "graph", "flowchart":
            return .flowchart(try FlowchartParser.parse(header: header, body: body, offset: headerIndex + 2))
        case "sequencediagram":
            return .sequence(try SequenceParser.parse(body: body, offset: headerIndex + 2))
        default:
            throw MermaidParseError(
                line: headerIndex + 1,
                message: "\(keyword) diagrams are not supported yet. Marker renders flowchart and sequenceDiagram."
            )
        }
    }

    /// Which diagram types exist, for the fallback message.
    public static func diagramKeyword(_ source: String) -> String? {
        source
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty && !$0.hasPrefix("%%") }?
            .split(separator: " ", maxSplits: 1).first
            .map(String.init)
    }
}

public struct MermaidParseError: Error, Sendable, Equatable {
    public let line: Int
    public let message: String

    public init(line: Int, message: String) {
        self.line = line
        self.message = message
    }
}

// MARK: - Flowchart

private enum FlowchartParser {

    static func parse(header: String, body: [String], offset: Int) throws -> Flowchart {
        let parts = header.split(separator: " ").map(String.init)
        // `graph` with no direction is top down, which is Mermaid's own default.
        let direction = parts.count > 1 ? Flowchart.Direction(keyword: parts[1]) ?? .topDown : .topDown

        var nodes: [String: Flowchart.Node] = [:]
        var order: [String] = []
        var edges: [Flowchart.Edge] = []

        func remember(_ node: Flowchart.Node) {
            if let existing = nodes[node.id] {
                // A later declaration with a real label wins, so `A --> B` followed by
                // `B[Label]` still labels B. Mermaid behaves the same way.
                if existing.label == existing.id, node.label != node.id {
                    nodes[node.id] = node
                }
            } else {
                nodes[node.id] = node
                order.append(node.id)
            }
        }

        for (index, raw) in body.enumerated() {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("%%") else { continue }
            // Styling directives are accepted and ignored rather than refused, so one
            // `classDef` does not cost the whole diagram.
            if isIgnorable(line) { continue }
            if line == "end" || line.hasPrefix("subgraph") {
                throw MermaidParseError(
                    line: offset + index,
                    message: "subgraphs are not supported yet"
                )
            }

            let statement = try parseStatement(line, lineNumber: offset + index)
            statement.nodes.forEach(remember)
            edges.append(contentsOf: statement.edges)
        }

        guard !order.isEmpty else {
            throw MermaidParseError(line: offset, message: "the diagram has no nodes")
        }
        return Flowchart(direction: direction, nodes: order.compactMap { nodes[$0] }, edges: edges)
    }

    private static func isIgnorable(_ line: String) -> Bool {
        let ignorable = ["classdef", "class ", "style ", "linkstyle", "click ", "direction "]
        let lowered = line.lowercased()
        return ignorable.contains { lowered.hasPrefix($0) }
    }

    private struct Statement {
        var nodes: [Flowchart.Node] = []
        var edges: [Flowchart.Edge] = []
    }

    /// One line: either a bare node declaration or a chain like `A --> B --> C`.
    ///
    /// A chain is read left to right, one link and one node at a time, so `A --> B
    /// --> C` yields two edges rather than three and the middle node is declared
    /// once.
    private static func parseStatement(_ line: String, lineNumber: Int) throws -> Statement {
        var statement = Statement()
        let (first, afterFirst) = try parseNode(Substring(line), lineNumber: lineNumber)
        statement.nodes.append(first)

        var current = first.id
        var remainder = afterFirst.drop { $0 == " " }

        while !remainder.isEmpty {
            guard let link = parseLink(remainder) else {
                throw MermaidParseError(
                    line: lineNumber,
                    message: "could not read <<<\(remainder.prefix(24))>>> as a link"
                )
            }
            let afterLink = link.rest.drop { $0 == " " }
            guard !afterLink.isEmpty else {
                throw MermaidParseError(
                    line: lineNumber,
                    message: "the link after \(current) has no target"
                )
            }

            let (target, afterTarget) = try parseNode(afterLink, lineNumber: lineNumber)
            statement.nodes.append(target)
            statement.edges.append(Flowchart.Edge(
                from: current, to: target.id,
                label: link.label, style: link.style, hasArrowHead: link.hasArrowHead
            ))
            current = target.id
            remainder = afterTarget.drop { $0 == " " }
        }

        return statement
    }

    /// Reads `A`, `A[Label]`, `A{Label}`, `A((Label))` and friends.
    private static func parseNode(
        _ input: Substring, lineNumber: Int
    ) throws -> (Flowchart.Node, Substring) {
        let trimmed = input.drop { $0 == " " }
        var identifier = ""
        var index = trimmed.startIndex
        while index < trimmed.endIndex {
            let character = trimmed[index]
            // No hyphen: it is the first character of every link, so allowing it in
            // an identifier makes `A-->B` unparseable without spaces, which is how
            // most Mermaid in the wild is written.
            guard character.isLetter || character.isNumber || character == "_" else { break }
            identifier.append(character)
            index = trimmed.index(after: index)
        }
        guard !identifier.isEmpty else {
            throw MermaidParseError(
                line: lineNumber,
                message: "expected a node name at <<<\(trimmed.prefix(20))>>>"
            )
        }

        guard index < trimmed.endIndex, let opening = Opening(trimmed[index...]) else {
            return (Flowchart.Node(id: identifier, label: identifier, shape: .rectangle), trimmed[index...])
        }

        let afterOpen = trimmed.index(index, offsetBy: opening.open.count)
        guard let closeRange = trimmed[afterOpen...].range(of: opening.close) else {
            throw MermaidParseError(
                line: lineNumber,
                message: "node \(identifier) is missing its closing \(opening.close)"
            )
        }
        let label = String(trimmed[afterOpen ..< closeRange.lowerBound])
        return (
            Flowchart.Node(id: identifier, label: unquote(label), shape: opening.shape),
            trimmed[closeRange.upperBound...]
        )
    }

    private struct Opening {
        let open: String
        let close: String
        let shape: Flowchart.NodeShape

        /// Longest opener first, so `((` is not read as `(`.
        static let all: [Opening] = [
            Opening(open: "([", close: "])", shape: .stadium),
            Opening(open: "[(", close: ")]", shape: .cylinder),
            Opening(open: "[[", close: "]]", shape: .subroutine),
            Opening(open: "((", close: "))", shape: .circle),
            Opening(open: "{{", close: "}}", shape: .hexagon),
            Opening(open: "[", close: "]", shape: .rectangle),
            Opening(open: "(", close: ")", shape: .rounded),
            Opening(open: "{", close: "}", shape: .diamond),
        ]

        init(open: String, close: String, shape: Flowchart.NodeShape) {
            self.open = open
            self.close = close
            self.shape = shape
        }

        init?(_ input: Substring) {
            guard let match = Opening.all.first(where: { input.hasPrefix($0.open) }) else { return nil }
            self = match
        }
    }

    private struct Link {
        let label: String?
        let style: Flowchart.EdgeStyle
        let hasArrowHead: Bool
        let rest: Substring
    }

    /// Reads `-->`, `---`, `-.->`, `==>`, and the `|label|` or `-- label -->` forms.
    private static func parseLink(_ input: Substring) -> Link? {
        var rest = input
        let style: Flowchart.EdgeStyle
        var hasArrowHead = true
        var label: String?

        // `-- label -->` and `-. label .->` put the label inside the link.
        if let inlineLabel = readInlineLabel(&rest) { label = inlineLabel }

        if rest.hasPrefix("-.") {
            style = .dotted
            rest = rest.drop { $0 == "-" || $0 == "." }
        } else if rest.hasPrefix("==") {
            style = .thick
            rest = rest.drop { $0 == "=" }
        } else if rest.hasPrefix("--") || rest.hasPrefix("-") {
            style = .solid
            rest = rest.drop { $0 == "-" }
        } else {
            return nil
        }

        if rest.hasPrefix(">") {
            rest = rest.dropFirst()
        } else {
            // `---` and `===` are lines with no head.
            hasArrowHead = false
        }

        rest = rest.drop { $0 == " " }
        // `|label|` sits after the arrow.
        if rest.hasPrefix("|"), let close = rest.dropFirst().firstIndex(of: "|") {
            label = unquote(String(rest[rest.index(after: rest.startIndex) ..< close]))
            rest = rest[rest.index(after: close)...]
        }

        return Link(label: label, style: style, hasArrowHead: hasArrowHead, rest: rest)
    }

    /// `-- text -->` and `-. text .->`: a label between two dash runs.
    private static func readInlineLabel(_ rest: inout Substring) -> String? {
        guard rest.hasPrefix("--") || rest.hasPrefix("-.") || rest.hasPrefix("==") else { return nil }
        let marker = rest.prefix(2)
        let afterMarker = rest.dropFirst(2)
        guard let labelStart = afterMarker.firstIndex(where: { $0 != " " }),
              afterMarker[labelStart] != ">" , afterMarker[labelStart] != "-",
              afterMarker[labelStart] != "." , afterMarker[labelStart] != "=" else { return nil }

        // The label runs until the next dash, dot or equals run that closes it.
        let tail = afterMarker[labelStart...]
        guard let closeStart = tail.range(of: marker == "-." ? "." : String(marker.first!)) else { return nil }
        let label = String(tail[tail.startIndex ..< closeStart.lowerBound]).trimmingCharacters(in: .whitespaces)
        guard !label.isEmpty else { return nil }
        rest = tail[closeStart.lowerBound...]
        return unquote(label)
    }

    private static func unquote(_ text: String) -> String {
        var value = text.trimmingCharacters(in: .whitespaces)
        if value.hasPrefix("\"") && value.hasSuffix("\"") && value.count >= 2 {
            value = String(value.dropFirst().dropLast())
        }
        return value.replacingOccurrences(of: "<br>", with: "\n")
            .replacingOccurrences(of: "<br/>", with: "\n")
    }
}

// MARK: - Sequence

private enum SequenceParser {

    static func parse(body: [String], offset: Int) throws -> SequenceDiagram {
        var title: String?
        var participants: [SequenceDiagram.Participant] = []
        var messages: [SequenceDiagram.Message] = []
        var notes: [SequenceDiagram.Note] = []

        func remember(_ id: String, label: String? = nil, isActor: Bool = false) {
            if let existing = participants.firstIndex(where: { $0.id == id }) {
                if let label { participants[existing].label = label }
                if isActor { participants[existing].isActor = true }
            } else {
                participants.append(.init(id: id, label: label ?? id, isActor: isActor))
            }
        }

        for (index, raw) in body.enumerated() {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("%%") else { continue }
            let lowered = line.lowercased()

            if lowered.hasPrefix("title ") {
                title = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces)
                continue
            }
            if lowered.hasPrefix("participant ") || lowered.hasPrefix("actor ") {
                let isActor = lowered.hasPrefix("actor ")
                let declaration = String(line.dropFirst(isActor ? 6 : 12))
                    .trimmingCharacters(in: .whitespaces)
                if let asRange = declaration.range(of: " as ") {
                    remember(
                        String(declaration[declaration.startIndex ..< asRange.lowerBound])
                            .trimmingCharacters(in: .whitespaces),
                        label: String(declaration[asRange.upperBound...])
                            .trimmingCharacters(in: .whitespaces),
                        isActor: isActor
                    )
                } else {
                    remember(declaration, isActor: isActor)
                }
                continue
            }
            if lowered.hasPrefix("note ") {
                if let note = parseNote(line, afterMessage: messages.count - 1) {
                    notes.append(note)
                }
                continue
            }
            // Blocks and lifecycle keywords are accepted and skipped so one of them
            // does not cost the whole diagram.
            if ["activate", "deactivate", "loop", "alt", "else", "opt", "par", "and", "end", "rect", "autonumber"]
                .contains(where: { lowered == $0 || lowered.hasPrefix($0 + " ") }) {
                continue
            }

            guard let message = parseMessage(line) else {
                throw MermaidParseError(
                    line: offset + index,
                    message: "could not read <<<\(line)>>> as a message"
                )
            }
            remember(message.from)
            remember(message.to)
            messages.append(message)
        }

        guard !participants.isEmpty else {
            throw MermaidParseError(line: offset, message: "the diagram has no participants")
        }
        return SequenceDiagram(title: title, participants: participants, messages: messages, notes: notes)
    }

    /// Longest arrow first, so `-->>` is not read as `-->`.
    private static let arrows: [(token: String, style: SequenceDiagram.ArrowStyle)] = [
        ("-->>", .dotted),
        ("->>", .solid),
        ("--x", .cross),
        ("-x", .cross),
        ("-->", .dottedOpen),
        ("->", .solidOpen),
    ]

    private static func parseMessage(_ line: String) -> SequenceDiagram.Message? {
        for arrow in arrows {
            guard let range = line.range(of: arrow.token) else { continue }
            var from = String(line[line.startIndex ..< range.lowerBound]).trimmingCharacters(in: .whitespaces)
            var tail = String(line[range.upperBound...])

            var text = ""
            if let colon = tail.firstIndex(of: ":") {
                text = String(tail[tail.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
                tail = String(tail[tail.startIndex ..< colon])
            }
            var to = tail.trimmingCharacters(in: .whitespaces)

            // `A->>+B` activates B, `A->>-B` deactivates.
            var activates = false
            var deactivates = false
            if to.hasPrefix("+") { activates = true; to.removeFirst() }
            if to.hasPrefix("-") { deactivates = true; to.removeFirst() }
            if from.hasSuffix("+") { activates = true; from.removeLast() }
            if from.hasSuffix("-") { deactivates = true; from.removeLast() }

            guard !from.isEmpty, !to.isEmpty else { return nil }
            return SequenceDiagram.Message(
                from: from.trimmingCharacters(in: .whitespaces),
                to: to.trimmingCharacters(in: .whitespaces),
                text: text,
                style: arrow.style,
                activates: activates,
                deactivates: deactivates
            )
        }
        return nil
    }

    private static func parseNote(_ line: String, afterMessage: Int) -> SequenceDiagram.Note? {
        guard let colon = line.firstIndex(of: ":") else { return nil }
        let head = String(line[line.startIndex ..< colon]).trimmingCharacters(in: .whitespaces)
        let text = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
        let lowered = head.lowercased()

        func targets(after prefix: String) -> [String] {
            String(head.dropFirst(prefix.count))
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        }

        if lowered.hasPrefix("note left of ") {
            guard let target = targets(after: "note left of ").first else { return nil }
            return .init(placement: .leftOf(target), text: text, afterMessage: afterMessage)
        }
        if lowered.hasPrefix("note right of ") {
            guard let target = targets(after: "note right of ").first else { return nil }
            return .init(placement: .rightOf(target), text: text, afterMessage: afterMessage)
        }
        if lowered.hasPrefix("note over ") {
            let over = targets(after: "note over ")
            guard !over.isEmpty else { return nil }
            return .init(placement: .over(over), text: text, afterMessage: afterMessage)
        }
        return nil
    }
}
