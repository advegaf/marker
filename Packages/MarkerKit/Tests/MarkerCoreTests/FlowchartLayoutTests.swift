import Testing
import CoreGraphics
@testable import MarkerCore

// Geometry is asserted directly rather than compared as pixels. A pixel diff says
// something moved; a coordinate assertion says what, and it does not break when a
// font ships a new version.

private func layout(_ source: String) throws -> (Flowchart, MermaidScene) {
    guard case .flowchart(let chart) = try MermaidParser.parse(source) else {
        throw MermaidParseError(line: 0, message: "not a flowchart")
    }
    return (chart, FlowchartLayout.scene(for: chart, measure: .deterministic))
}

private func ranks(_ source: String) throws -> [String: Int] {
    guard case .flowchart(let chart) = try MermaidParser.parse(source) else {
        throw MermaidParseError(line: 0, message: "not a flowchart")
    }
    return FlowchartLayout.assignRanks(chart)
}

@Test func rankIsTheLongestPathNotTheShortest() throws {
    // D must sit below C, not beside B, or the diagram claims A and C are peers.
    let table = try ranks("""
    graph TD
        A --> B
        A --> C
        C --> D
        B --> D
    """)
    #expect(table["A"] == 0)
    #expect(table["B"] == 1)
    #expect(table["C"] == 1)
    #expect(table["D"] == 2)
}

@Test func aLongChainRanksMonotonically() throws {
    let table = try ranks("graph TD\nA-->B-->C-->D-->E")
    #expect(table["A"] == 0 && table["B"] == 1 && table["C"] == 2 && table["D"] == 3 && table["E"] == 4)
}

@Test func aCycleTerminatesInsteadOfHanging() throws {
    // State machines in READMEs loop constantly. Refusing to lay one out is worse
    // than laying it out imperfectly.
    let table = try ranks("graph TD\nA-->B\nB-->C\nC-->A")
    #expect(table.count == 3)
}

@Test func aSelfEdgeDoesNotAffectRank() throws {
    let table = try ranks("graph TD\nA-->A\nA-->B")
    #expect(table["A"] == 0)
    #expect(table["B"] == 1)
}

@Test func noTwoBoxesOverlap() throws {
    // The one thing a diagram may never do.
    for source in [
        "graph TD\nA[Open file] --> B{Markdown?}\nB -->|yes| C[Parse]\nB -->|no| D[Print]\nC --> E[Render]\nD --> E",
        "graph LR\nA-->B-->C-->D\nA-->D",
        "graph TD\nA-->B\nA-->C\nA-->D\nA-->E\nB-->F\nC-->F\nD-->F\nE-->F",
    ] {
        let (_, scene) = try layout(source)
        let boxes = scene.shapes.map(\.frame)
        for (i, a) in boxes.enumerated() {
            for b in boxes[(i + 1)...] {
                #expect(!a.insetBy(dx: 1, dy: 1).intersects(b.insetBy(dx: 1, dy: 1)),
                        "boxes overlap in <<<\(source.prefix(24))>>>")
            }
        }
    }
}

@Test func topDownPutsLaterRanksLower() throws {
    let (chart, scene) = try layout("graph TD\nA-->B-->C")
    let frames = frameByNode(chart, scene)
    #expect(frames["A"]!.midY < frames["B"]!.midY)
    #expect(frames["B"]!.midY < frames["C"]!.midY)
    // And they stay in one column.
    #expect(abs(frames["A"]!.midX - frames["C"]!.midX) < 2)
}

@Test func leftRightPutsLaterRanksFurtherRight() throws {
    let (chart, scene) = try layout("graph LR\nA-->B-->C")
    let frames = frameByNode(chart, scene)
    #expect(frames["A"]!.midX < frames["B"]!.midX)
    #expect(frames["B"]!.midX < frames["C"]!.midX)
    #expect(abs(frames["A"]!.midY - frames["C"]!.midY) < 2)
}

@Test func bottomUpIsTopDownMirrored() throws {
    let (chart, scene) = try layout("graph BT\nA-->B-->C")
    let frames = frameByNode(chart, scene)
    #expect(frames["A"]!.midY > frames["C"]!.midY, "BT should put the source at the bottom")
}

@Test func rightLeftIsLeftRightMirrored() throws {
    let (chart, scene) = try layout("graph RL\nA-->B-->C")
    let frames = frameByNode(chart, scene)
    #expect(frames["A"]!.midX > frames["C"]!.midX)
}

@Test func everythingFitsInsideTheReportedSize() throws {
    // The renderer allocates a bitmap from scene.size, so anything outside it is
    // silently clipped.
    let (_, scene) = try layout("""
    graph TD
        A[A long label that widens its box] --> B{Decision?}
        B -->|a long edge label| C[Third]
        B --> D((Circle))
    """)
    for shape in scene.shapes {
        #expect(shape.frame.minX >= 0 && shape.frame.minY >= 0)
        #expect(shape.frame.maxX <= scene.size.width + 0.5)
        #expect(shape.frame.maxY <= scene.size.height + 0.5)
    }
    for path in scene.paths {
        for point in path.points {
            #expect(point.x >= -0.5 && point.x <= scene.size.width + 0.5)
            #expect(point.y >= -0.5 && point.y <= scene.size.height + 0.5)
        }
    }
}

@Test func aLongerLabelMakesAWiderBox() throws {
    let (chart, scene) = try layout("graph TD\nA[x] --> B[a much longer label here]")
    let frames = frameByNode(chart, scene)
    #expect(frames["B"]!.width > frames["A"]!.width)
}

@Test func diamondsGetSlackForTheirPoints() throws {
    // A diamond holds its label across the middle, so the same text needs a wider
    // box than a rectangle or the words stick out of the points.
    let (chart, scene) = try layout("graph TD\nA[same text] --> B{same text}")
    let frames = frameByNode(chart, scene)
    #expect(frames["B"]!.width > frames["A"]!.width)
}

@Test func edgesStartAndEndOnBoxBorders() throws {
    // An arrow that starts at the centre draws through its own box.
    let (chart, scene) = try layout("graph TD\nA-->B")
    let frames = frameByNode(chart, scene)
    let path = try #require(scene.paths.first)
    let start = path.points.first!
    let end = path.points.last!
    #expect(!frames["A"]!.insetBy(dx: 1, dy: 1).contains(start))
    #expect(!frames["B"]!.insetBy(dx: 1, dy: 1).contains(end))
}

@Test func edgeStylesReachTheScene() throws {
    let (_, scene) = try layout("graph LR\nA-->B\nB-.->C\nC==>D\nD---E")
    #expect(scene.paths.count == 4)
    if case .dashed = scene.paths[1].stroke {} else { Issue.record("dotted edge lost its dash") }
    if case .solid(let width) = scene.paths[2].stroke { #expect(width > 2) }
    #expect(scene.paths[3].hasArrowHead == false)
}

@Test func edgeLabelsGetABackgroundSoTheLineDoesNotRunThroughThem() throws {
    let (_, scene) = try layout("graph TD\nA -->|yes| B")
    #expect(scene.labelBackgrounds.count == 1)
    let label = try #require(scene.texts.first { $0.role == .edgeLabel })
    #expect(label.string == "yes")
    #expect(scene.labelBackgrounds[0].intersects(label.frame))
}

@Test func layoutIsDeterministic() throws {
    // Two runs of the same source must agree, or screenshots churn on every build.
    let first = try layout("graph TD\nA-->B\nA-->C\nB-->D\nC-->D").1
    let second = try layout("graph TD\nA-->B\nA-->C\nB-->D\nC-->D").1
    #expect(first == second)
}

@Test func barycentreOrderingReducesCrossings() throws {
    // Declared so the naive order crosses: A connects to the second child, B to the
    // first. After ordering, the two ranks should agree.
    guard case .flowchart(let chart) = try MermaidParser.parse("""
    graph TD
        A --> Y
        B --> X
    """) else { return }
    let table = FlowchartLayout.assignRanks(chart)
    let layers = FlowchartLayout.orderWithinRanks(chart, ranks: table)
    #expect(layers.count == 2)
    // Whatever order rank 0 settles on, rank 1 must mirror it.
    let top = layers[0]
    let bottom = layers[1]
    let expected = top.map { $0 == "A" ? "Y" : "X" }
    #expect(bottom == expected, "ordering left a crossing: \(top) over \(bottom)")
}

private func frameByNode(_ chart: Flowchart, _ scene: MermaidScene) -> [String: CGRect] {
    var table: [String: CGRect] = [:]
    // Shapes are emitted in chart.nodes order.
    for (index, node) in chart.nodes.enumerated() where index < scene.shapes.count {
        table[node.id] = scene.shapes[index].frame
    }
    return table
}
