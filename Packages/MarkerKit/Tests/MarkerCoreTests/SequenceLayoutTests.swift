import Testing
import CoreGraphics
@testable import MarkerCore

private func sequenceLayout(_ source: String) throws -> (SequenceDiagram, MermaidScene) {
    guard case .sequence(let diagram) = try MermaidParser.parse(source) else {
        throw MermaidParseError(line: 0, message: "not a sequence")
    }
    return (diagram, SequenceLayout.scene(for: diagram, measure: .deterministic))
}

@Test func participantsBecomeColumnsInDeclarationOrder() throws {
    let (_, scene) = try sequenceLayout("""
    sequenceDiagram
        participant A as Alice
        participant B as Bob
        participant C as Carol
        A->>B: one
    """)
    let heads = scene.shapes.filter { if case .rectangle = $0.kind { return true }; return false }
    #expect(heads.count == 3)
    let xs = heads.map(\.frame.midX)
    #expect(xs == xs.sorted(), "columns are not in declaration order")
}

@Test func everyParticipantGetsALifeline() throws {
    let (_, scene) = try sequenceLayout("sequenceDiagram\n  A->>B: one\n  B->>C: two")
    // Lifelines are the vertical dashed paths.
    let lifelines = scene.paths.filter { path in
        guard case .dashed = path.stroke, path.points.count == 2 else { return false }
        return abs(path.points[0].x - path.points[1].x) < 0.5
    }
    #expect(lifelines.count == 3)
}

@Test func messagesRunDownThePageInSourceOrder() throws {
    let (_, scene) = try sequenceLayout("""
    sequenceDiagram
        A->>B: first
        B->>A: second
        A->>B: third
    """)
    let messages = scene.paths.filter { $0.hasArrowHead }
    #expect(messages.count == 3)
    let ys = messages.map { $0.points[0].y }
    #expect(ys == ys.sorted(), "messages are out of order down the page")
}

@Test func aSelfCallLoopsInsteadOfVanishing() throws {
    // An arrow from a point to itself has zero length and draws nothing.
    let (_, scene) = try sequenceLayout("sequenceDiagram\n  A->>A: think")
    let message = try #require(scene.paths.first { $0.hasArrowHead })
    #expect(message.points.count == 4, "a self call should be routed as a loop")
    let xs = message.points.map(\.x)
    #expect(xs.max()! > xs.min()! + 10, "the loop has no reach")
}

@Test func messageTextGetsABackgroundSoLifelinesDoNotRunThroughIt() throws {
    let (_, scene) = try sequenceLayout("sequenceDiagram\n  A->>B: a message")
    #expect(scene.labelBackgrounds.count == 1)
    let label = try #require(scene.texts.first { $0.role == .edgeLabel })
    #expect(label.string == "a message")
}

@Test func dottedArrowsKeepTheirStyle() throws {
    let (_, scene) = try sequenceLayout("sequenceDiagram\n  A->>B: solid\n  B-->>A: dotted")
    let messages = scene.paths.filter { $0.hasArrowHead }
    if case .solid = messages[0].stroke {} else { Issue.record("first message lost its solid stroke") }
    if case .dashed = messages[1].stroke {} else { Issue.record("second message lost its dash") }
}

@Test func openArrowsAreMarkedOpen() throws {
    let (_, scene) = try sequenceLayout("sequenceDiagram\n  A->B: open\n  A->>B: closed")
    let messages = scene.paths.filter { $0.hasArrowHead }
    #expect(messages[0].isOpenHead)
    #expect(messages[1].isOpenHead == false)
}

@Test func crossMessagesGetACross() throws {
    let (_, scene) = try sequenceLayout("sequenceDiagram\n  A-xB: failed")
    let message = try #require(scene.paths.first { $0.hasArrowHead })
    #expect(message.isCrossHead)
}

@Test func notesBecomeTheirOwnShape() throws {
    let (_, scene) = try sequenceLayout("""
    sequenceDiagram
        A->>B: hello
        Note right of B: thinking
    """)
    let notes = scene.shapes.filter { $0.kind == .note }
    #expect(notes.count == 1)
    #expect(scene.texts.contains { $0.role == .note && $0.string == "thinking" })
}

@Test func aTitleSitsAboveEverything() throws {
    let (_, scene) = try sequenceLayout("sequenceDiagram\n  title Conversation\n  A->>B: hi")
    let title = try #require(scene.texts.first { $0.role == .title })
    #expect(title.string == "Conversation")
    let heads = scene.shapes.filter { if case .rectangle = $0.kind { return true }; return false }
    #expect(heads.allSatisfy { $0.frame.minY > title.frame.minY })
}

@Test func sequenceFitsInsideTheReportedSize() throws {
    let (_, scene) = try sequenceLayout("""
    sequenceDiagram
        participant U as A user with a long name
        participant S as Server
        U->>S: a fairly long message text here
        S-->>U: another long reply
        S->>S: internal work
        Note over U,S: a note spanning both
    """)
    for shape in scene.shapes {
        #expect(shape.frame.minX >= -0.5 && shape.frame.maxX <= scene.size.width + 0.5)
        #expect(shape.frame.minY >= -0.5 && shape.frame.maxY <= scene.size.height + 0.5)
    }
    for path in scene.paths {
        for point in path.points {
            #expect(point.x >= -0.5 && point.x <= scene.size.width + 0.5)
            #expect(point.y >= -0.5 && point.y <= scene.size.height + 0.5)
        }
    }
}

@Test func columnsAreWideEnoughForTheirNames() throws {
    let (diagram, scene) = try sequenceLayout("""
    sequenceDiagram
        participant A as A very long participant name
        participant B as B
        A->>B: hi
    """)
    let heads = scene.shapes.filter { if case .rectangle = $0.kind { return true }; return false }
    let label = TextMeasure.deterministic.size(diagram.participants[0].label, 14).width
    #expect(heads[0].frame.width > label, "the name does not fit its box")
}

@Test func sequenceLayoutIsDeterministic() throws {
    let first = try sequenceLayout("sequenceDiagram\n  A->>B: one\n  B-->>A: two").1
    let second = try sequenceLayout("sequenceDiagram\n  A->>B: one\n  B-->>A: two").1
    #expect(first == second)
}
