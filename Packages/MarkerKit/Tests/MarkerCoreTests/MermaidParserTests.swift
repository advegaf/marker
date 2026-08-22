import Testing
@testable import MarkerCore

// The parser is the half of the engine that can be wrong quietly: a mis-read link
// still draws, just not the diagram the author wrote.

private func flowchart(_ source: String) throws -> Flowchart {
    guard case .flowchart(let chart) = try MermaidParser.parse(source) else {
        Issue.record("expected a flowchart"); throw MermaidParseError(line: 0, message: "not a flowchart")
    }
    return chart
}

private func sequence(_ source: String) throws -> SequenceDiagram {
    guard case .sequence(let diagram) = try MermaidParser.parse(source) else {
        Issue.record("expected a sequence"); throw MermaidParseError(line: 0, message: "not a sequence")
    }
    return diagram
}

@Test func readsDirectionsInEverySpelling() throws {
    #expect(try flowchart("graph TD\nA-->B").direction == .topDown)
    #expect(try flowchart("graph TB\nA-->B").direction == .topDown)
    #expect(try flowchart("graph BT\nA-->B").direction == .bottomUp)
    #expect(try flowchart("graph LR\nA-->B").direction == .leftRight)
    #expect(try flowchart("flowchart RL\nA-->B").direction == .rightLeft)
    // Mermaid's own default when none is given.
    #expect(try flowchart("graph\nA-->B").direction == .topDown)
}

@Test func readsEveryNodeShape() throws {
    let chart = try flowchart("""
    graph TD
        A[rect] --> B(round)
        B --> C{diamond}
        C --> D((circle))
        D --> E([stadium])
        E --> F[[sub]]
        F --> G[(cyl)]
        G --> H{{hex}}
    """)
    let shapes = ["A": Flowchart.NodeShape.rectangle, "B": .rounded, "C": .diamond,
                  "D": .circle, "E": .stadium, "F": .subroutine, "G": .cylinder, "H": .hexagon]
    for (id, shape) in shapes {
        #expect(chart.node(id: id)?.shape == shape, "\(id) had the wrong shape")
    }
}

@Test func chainsProduceOneEdgePerLink() throws {
    // A --> B --> C is two edges, and B is declared once.
    let chart = try flowchart("graph TD\nA --> B --> C")
    #expect(chart.edges.count == 2)
    #expect(chart.nodes.count == 3)
    #expect(chart.edges.map(\.from) == ["A", "B"])
    #expect(chart.edges.map(\.to) == ["B", "C"])
}

@Test func readsEdgeStylesAndHeads() throws {
    let chart = try flowchart("""
    graph LR
        A --> B
        B --- C
        C -.-> D
        D ==> E
    """)
    #expect(chart.edges[0].style == .solid)
    #expect(chart.edges[0].hasArrowHead)
    #expect(chart.edges[1].hasArrowHead == false)
    #expect(chart.edges[2].style == .dotted)
    #expect(chart.edges[3].style == .thick)
}

@Test func readsPipeLabels() throws {
    let chart = try flowchart("""
    graph TD
        B -->|yes| C
        B -->|no| D
    """)
    #expect(chart.edges.map(\.label) == ["yes", "no"])
}

@Test func readsInlineLabels() throws {
    let chart = try flowchart("graph TD\n  A -- goes to --> B")
    #expect(chart.edges.first?.label == "goes to")
    #expect(chart.edges.first?.to == "B")
}

@Test func aLaterDeclarationSuppliesAMissingLabel() throws {
    // `A --> B` then `B[Label]` must label B, the way Mermaid does.
    let chart = try flowchart("graph TD\nA --> B\nB[Real label]")
    #expect(chart.node(id: "B")?.label == "Real label")
}

@Test func quotedLabelsAndLineBreaksAreUnwrapped() throws {
    let chart = try flowchart("graph TD\nA[\"Quoted label\"] --> B[one<br>two]")
    #expect(chart.node(id: "A")?.label == "Quoted label")
    #expect(chart.node(id: "B")?.label == "one\ntwo")
}

@Test func stylingDirectivesAreIgnoredNotRefused() throws {
    // One classDef should not cost the whole diagram.
    let chart = try flowchart("""
    graph TD
        A --> B
        classDef big fill:#f9f
        class A big
        style B stroke:#333
        linkStyle 0 stroke:#000
    """)
    #expect(chart.edges.count == 1)
}

@Test func commentsAreSkipped() throws {
    let chart = try flowchart("%% a comment\ngraph TD\n%% another\nA --> B")
    #expect(chart.edges.count == 1)
}

@Test func unsupportedDiagramTypesNameThemselves() {
    #expect(throws: MermaidParseError.self) {
        try MermaidParser.parse("gantt\n  title A")
    }
    do {
        _ = try MermaidParser.parse("gantt\n  title A")
    } catch let error as MermaidParseError {
        // The message has to say what is missing, since it is shown to the reader.
        #expect(error.message.contains("gantt"))
        #expect(error.message.contains("flowchart"))
    } catch {
        Issue.record("wrong error type")
    }
}

@Test func subgraphsAreRefusedClearly() {
    do {
        _ = try MermaidParser.parse("graph TD\nsubgraph one\nA --> B\nend")
        Issue.record("expected a refusal")
    } catch let error as MermaidParseError {
        #expect(error.message.contains("subgraph"))
    } catch {
        Issue.record("wrong error type")
    }
}

@Test func emptyAndGarbageInputRaise() {
    #expect(throws: MermaidParseError.self) { try MermaidParser.parse("") }
    #expect(throws: MermaidParseError.self) { try MermaidParser.parse("graph TD\n???") }
    #expect(throws: MermaidParseError.self) { try MermaidParser.parse("graph TD\nA -->") }
}

// MARK: Sequence

@Test func readsParticipantsInDeclarationOrder() throws {
    let diagram = try sequence("""
    sequenceDiagram
        participant A as Alice
        participant B as Bob
        A->>B: Hello
    """)
    #expect(diagram.participants.map(\.id) == ["A", "B"])
    #expect(diagram.participants.map(\.label) == ["Alice", "Bob"])
}

@Test func participantsAreInventedFromMessagesWhenNotDeclared() throws {
    let diagram = try sequence("sequenceDiagram\n  Alice->>Bob: Hi\n  Bob->>Carol: Hi")
    #expect(diagram.participants.map(\.id) == ["Alice", "Bob", "Carol"])
}

@Test func readsEveryArrowStyle() throws {
    let diagram = try sequence("""
    sequenceDiagram
        A->>B: solid
        A-->>B: dotted
        A->B: open
        A-->B: dotted open
        A-xB: cross
    """)
    #expect(diagram.messages.map(\.style) == [.solid, .dotted, .solidOpen, .dottedOpen, .cross])
    #expect(diagram.messages.map(\.text) == ["solid", "dotted", "open", "dotted open", "cross"])
}

@Test func readsActivationSuffixes() throws {
    let diagram = try sequence("sequenceDiagram\n  A->>+B: start\n  B-->>-A: done")
    #expect(diagram.messages[0].activates)
    #expect(diagram.messages[1].deactivates)
    #expect(diagram.messages[0].to == "B")
    #expect(diagram.messages[1].to == "A")
}

@Test func readsNotesAndTitles() throws {
    let diagram = try sequence("""
    sequenceDiagram
        title A conversation
        A->>B: Hello
        Note right of B: thinking
        Note over A,B: both
    """)
    #expect(diagram.title == "A conversation")
    #expect(diagram.notes.count == 2)
    if case .rightOf(let target) = diagram.notes[0].placement { #expect(target == "B") }
    if case .over(let targets) = diagram.notes[1].placement { #expect(targets == ["A", "B"]) }
}

@Test func blockKeywordsAreSkippedNotRefused() throws {
    let diagram = try sequence("""
    sequenceDiagram
        autonumber
        loop every minute
            A->>B: poll
        end
        alt found
            B-->>A: yes
        else missing
            B-->>A: no
        end
    """)
    #expect(diagram.messages.count == 3)
}
