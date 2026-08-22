import CoreGraphics
import Foundation

/// Lays a flowchart out as a layered graph.
///
/// The classic Sugiyama shape, minus the parts that need a solver: rank by longest
/// path, order within a rank by barycentre to reduce crossings, then place. It will
/// not match mermaid-js pixel for pixel and does not try to. It has to be readable,
/// stable, and never overlap two boxes.
public enum FlowchartLayout {

    public static func scene(
        for chart: Flowchart,
        style: MermaidStyle = MermaidStyle(),
        measure: TextMeasure = .deterministic
    ) -> MermaidScene {
        let sizes = nodeSizes(chart, style: style, measure: measure)
        let ranks = assignRanks(chart)
        let ordered = orderWithinRanks(chart, ranks: ranks)
        let positions = place(chart, order: ordered, sizes: sizes, style: style)
        return draw(chart, positions: positions, sizes: sizes, style: style, measure: measure)
    }

    // MARK: Sizing

    private static func nodeSizes(
        _ chart: Flowchart, style: MermaidStyle, measure: TextMeasure
    ) -> [String: CGSize] {
        var sizes: [String: CGSize] = [:]
        for node in chart.nodes {
            let text = measure.size(node.label, style.fontSize)
            var width = max(text.width + style.nodePaddingX * 2, style.minNodeWidth)
            var height = max(text.height + style.nodePaddingY * 2, style.minNodeHeight)

            switch node.shape {
            case .diamond, .hexagon:
                // A diamond only contains its label across the middle, so it needs
                // real slack in both axes or the text pokes out of the points.
                width *= 1.45
                height *= 1.35
            case .circle:
                let diameter = max(width, height) * 1.1
                width = diameter
                height = diameter
            case .cylinder:
                height += style.fontSize * 0.6
            case .subroutine:
                width += style.fontSize * 0.8
            case .rectangle, .rounded, .stadium:
                break
            }
            sizes[node.id] = CGSize(width: width.rounded(), height: height.rounded())
        }
        return sizes
    }

    // MARK: Ranking

    /// Longest path from any source. Cycles are broken by visiting in declaration
    /// order and refusing to revisit, so a cyclic graph still lays out instead of
    /// hanging, which matters because a diagram in a README is often a state loop.
    static func assignRanks(_ chart: Flowchart) -> [String: Int] {
        var incoming: [String: [String]] = [:]
        var outgoing: [String: [String]] = [:]
        for edge in chart.edges where edge.from != edge.to {
            outgoing[edge.from, default: []].append(edge.to)
            incoming[edge.to, default: []].append(edge.from)
        }

        var rank: [String: Int] = [:]
        var visiting: Set<String> = []

        func resolve(_ id: String) -> Int {
            if let known = rank[id] { return known }
            // A node already on the stack is a cycle. Treat it as rank 0 for the
            // purposes of this walk rather than recursing forever.
            if visiting.contains(id) { return 0 }
            visiting.insert(id)
            defer { visiting.remove(id) }

            let parents = incoming[id] ?? []
            let value = parents.isEmpty ? 0 : (parents.map { resolve($0) + 1 }.max() ?? 0)
            rank[id] = value
            return value
        }

        for node in chart.nodes { _ = resolve(node.id) }
        return rank
    }

    /// Barycentre ordering: repeatedly sort each rank by the average position of the
    /// nodes it connects to in the neighbouring rank. A handful of passes removes
    /// most crossings and is stable, which matters more here than optimality.
    static func orderWithinRanks(_ chart: Flowchart, ranks: [String: Int]) -> [[String]] {
        let maxRank = ranks.values.max() ?? 0
        var layers: [[String]] = Array(repeating: [], count: maxRank + 1)
        // Seeded in declaration order so the result is deterministic.
        for node in chart.nodes {
            layers[ranks[node.id] ?? 0].append(node.id)
        }

        var neighboursAbove: [String: [String]] = [:]
        var neighboursBelow: [String: [String]] = [:]
        for edge in chart.edges where edge.from != edge.to {
            neighboursAbove[edge.to, default: []].append(edge.from)
            neighboursBelow[edge.from, default: []].append(edge.to)
        }

        func positions(in layer: [String]) -> [String: Double] {
            var table: [String: Double] = [:]
            for (index, id) in layer.enumerated() { table[id] = Double(index) }
            return table
        }

        for pass in 0 ..< 4 {
            let downward = pass % 2 == 0
            let indices = downward ? Array(1 ..< layers.count) : Array((0 ..< max(layers.count - 1, 0)).reversed())
            for index in indices {
                let reference = positions(in: layers[downward ? index - 1 : index + 1])
                let neighbours = downward ? neighboursAbove : neighboursBelow
                let current = positions(in: layers[index])
                layers[index].sort { left, right in
                    let a = barycentre(left, neighbours: neighbours, reference: reference) ?? current[left] ?? 0
                    let b = barycentre(right, neighbours: neighbours, reference: reference) ?? current[right] ?? 0
                    if a == b { return (current[left] ?? 0) < (current[right] ?? 0) }
                    return a < b
                }
            }
        }
        return layers
    }

    private static func barycentre(
        _ id: String, neighbours: [String: [String]], reference: [String: Double]
    ) -> Double? {
        let connected = (neighbours[id] ?? []).compactMap { reference[$0] }
        guard !connected.isEmpty else { return nil }
        return connected.reduce(0, +) / Double(connected.count)
    }

    // MARK: Placement

    private static func place(
        _ chart: Flowchart, order: [[String]], sizes: [String: CGSize], style: MermaidStyle
    ) -> [String: CGPoint] {
        let vertical = chart.direction.isVertical

        // Along the flow axis, each rank sits after the tallest (or widest) node of
        // the rank before it.
        var rankOffsets: [CGFloat] = []
        var flowCursor: CGFloat = style.padding
        for layer in order {
            let extent = layer.compactMap { sizes[$0] }
                .map { vertical ? $0.height : $0.width }.max() ?? style.minNodeHeight
            rankOffsets.append(flowCursor + extent / 2)
            flowCursor += extent + style.rankSpacing
        }

        // Across the rank, nodes are laid end to end and the whole rank is centred,
        // so a two node rank sits under the middle of a five node one.
        var crossExtents: [CGFloat] = []
        for layer in order {
            let total = layer.compactMap { sizes[$0] }
                .map { vertical ? $0.width : $0.height }
                .reduce(0, +) + style.nodeSpacing * CGFloat(max(layer.count - 1, 0))
            crossExtents.append(total)
        }
        let widest = crossExtents.max() ?? 0

        var positions: [String: CGPoint] = [:]
        for (rankIndex, layer) in order.enumerated() {
            var cross = style.padding + (widest - crossExtents[rankIndex]) / 2
            for id in layer {
                guard let size = sizes[id] else { continue }
                let extent = vertical ? size.width : size.height
                let centre = cross + extent / 2
                positions[id] = vertical
                    ? CGPoint(x: centre, y: rankOffsets[rankIndex])
                    : CGPoint(x: rankOffsets[rankIndex], y: centre)
                cross += extent + style.nodeSpacing
            }
        }

        // Bottom-up and right-left are the same layout mirrored, which is cheaper and
        // less error prone than threading a sign through every calculation above.
        if chart.direction == .bottomUp || chart.direction == .rightLeft {
            let bound = vertical ? flowCursor - style.rankSpacing + style.padding
                                 : flowCursor - style.rankSpacing + style.padding
            for (id, point) in positions {
                positions[id] = vertical
                    ? CGPoint(x: point.x, y: bound - point.y)
                    : CGPoint(x: bound - point.x, y: point.y)
            }
        }
        return positions
    }

    // MARK: Drawing

    private static func draw(
        _ chart: Flowchart,
        positions: [String: CGPoint],
        sizes: [String: CGSize],
        style: MermaidStyle,
        measure: TextMeasure
    ) -> MermaidScene {
        var shapes: [MermaidScene.Shape] = []
        var texts: [MermaidScene.Text] = []
        var paths: [MermaidScene.Path] = []
        var labelBackgrounds: [CGRect] = []

        var maxX: CGFloat = 0
        var maxY: CGFloat = 0

        for node in chart.nodes {
            guard let centre = positions[node.id], let size = sizes[node.id] else { continue }
            let frame = CGRect(
                x: centre.x - size.width / 2, y: centre.y - size.height / 2,
                width: size.width, height: size.height
            )
            shapes.append(MermaidScene.Shape(kind: kind(for: node.shape, style: style), frame: frame))
            texts.append(MermaidScene.Text(string: node.label, frame: frame, role: .nodeLabel))
            maxX = max(maxX, frame.maxX)
            maxY = max(maxY, frame.maxY)
        }

        for edge in chart.edges {
            guard let from = positions[edge.from], let to = positions[edge.to],
                  let fromSize = sizes[edge.from], let toSize = sizes[edge.to] else { continue }

            let start = borderPoint(from: from, size: fromSize, towards: to)
            let end = borderPoint(from: to, size: toSize, towards: from)
            let points = route(from: start, to: end, vertical: chart.direction.isVertical)

            paths.append(MermaidScene.Path(
                points: points,
                stroke: stroke(for: edge.style, style: style),
                hasArrowHead: edge.hasArrowHead
            ))

            if let label = edge.label, !label.isEmpty {
                let textSize = measure.size(label, style.edgeLabelFontSize)
                let midpoint = points[points.count / 2]
                let box = CGRect(
                    x: midpoint.x - textSize.width / 2 - 4,
                    y: midpoint.y - textSize.height / 2 - 2,
                    width: textSize.width + 8,
                    height: textSize.height + 4
                )
                labelBackgrounds.append(box)
                texts.append(MermaidScene.Text(string: label, frame: box, role: .edgeLabel))
                maxX = max(maxX, box.maxX)
                maxY = max(maxY, box.maxY)
            }
        }

        return MermaidScene(
            size: CGSize(width: maxX + style.padding, height: maxY + style.padding),
            shapes: shapes,
            paths: paths,
            texts: texts,
            labelBackgrounds: labelBackgrounds
        )
    }

    private static func kind(for shape: Flowchart.NodeShape, style: MermaidStyle) -> MermaidScene.ShapeKind {
        switch shape {
        case .rectangle: return .rectangle(cornerRadius: 3)
        case .rounded: return .rectangle(cornerRadius: style.fontSize * 0.6)
        case .stadium: return .rectangle(cornerRadius: style.minNodeHeight)
        case .diamond: return .diamond
        case .circle: return .ellipse
        case .hexagon: return .hexagon
        case .subroutine: return .subroutine
        case .cylinder: return .cylinder
        }
    }

    private static func stroke(for edge: Flowchart.EdgeStyle, style: MermaidStyle) -> MermaidScene.Stroke {
        switch edge {
        case .solid: return .solid(width: 1.5)
        case .thick: return .solid(width: 3)
        case .dotted: return .dashed(width: 1.5, pattern: [5, 4])
        }
    }

    /// Where a line leaves a box: the intersection of the centre-to-centre line with
    /// the box's border, so an arrow touches the edge rather than the middle.
    static func borderPoint(from centre: CGPoint, size: CGSize, towards other: CGPoint) -> CGPoint {
        let dx = other.x - centre.x
        let dy = other.y - centre.y
        guard dx != 0 || dy != 0 else { return centre }

        let halfWidth = size.width / 2
        let halfHeight = size.height / 2
        let scaleX = dx == 0 ? CGFloat.greatestFiniteMagnitude : halfWidth / abs(dx)
        let scaleY = dy == 0 ? CGFloat.greatestFiniteMagnitude : halfHeight / abs(dy)
        let scale = min(scaleX, scaleY)
        return CGPoint(x: centre.x + dx * scale, y: centre.y + dy * scale)
    }

    /// An orthogonal route with one dog-leg, which reads as a diagram rather than a
    /// spider web. A straight line is used when the two ends already line up.
    static func route(from start: CGPoint, to end: CGPoint, vertical: Bool) -> [CGPoint] {
        let aligned = vertical ? abs(start.x - end.x) < 1 : abs(start.y - end.y) < 1
        if aligned { return [start, end] }

        if vertical {
            let midY = (start.y + end.y) / 2
            return [start, CGPoint(x: start.x, y: midY), CGPoint(x: end.x, y: midY), end]
        }
        let midX = (start.x + end.x) / 2
        return [start, CGPoint(x: midX, y: start.y), CGPoint(x: midX, y: end.y), end]
    }
}
