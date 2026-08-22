import Testing
@testable import MarkerCore

// The trigger rules matter more than the snippets. A menu that opens on every
// slash makes typing a URL or a file path infuriating, and one that never opens is
// invisible.

private func source(_ text: String) -> MarkdownSource { MarkdownSource(text) }

/// Caret position expressed as a byte offset, for readability in the tests.
private func token(_ text: String, caret: Int) -> Range<Int>? {
    SlashCommandInsertion.activeToken(at: caret, in: source(text))
}

@Test func aSlashAtTheStartOfALineOpensTheMenu() {
    #expect(token("/", caret: 1) == 0 ..< 1)
    #expect(token("/tab", caret: 4) == 0 ..< 4)
}

@Test func aSlashAfterASpaceOpensTheMenu() {
    #expect(token("some text /tab", caret: 14) == 10 ..< 14)
}

@Test func aSlashOnALaterLineOpensTheMenu() {
    let text = "first line\n/code"
    #expect(token(text, caret: text.utf8.count) == 11 ..< 16)
}

@Test func aSlashInsideAWordDoesNotOpenTheMenu() {
    // "and/or", a path, a URL. Opening a command menu in any of these would make
    // ordinary typing hostile.
    #expect(token("and/or", caret: 6) == nil)
    #expect(token("src/main", caret: 8) == nil)
    #expect(token("https://example", caret: 15) == nil)
}

@Test func theMenuClosesOnceThereIsWhitespaceAfterTheSlash() {
    // Typing "/ " means the person wanted a slash, not a command.
    #expect(token("/table now", caret: 10) == nil)
}

@Test func aVeryLongWordAfterASlashStopsBeingACommand() {
    let long = "/" + String(repeating: "x", count: 40)
    #expect(token(long, caret: long.utf8.count) == nil)
}

@Test func theQueryExcludesTheSlash() {
    let text = source("/tab")
    let range = try! #require(SlashCommandInsertion.activeToken(at: 4, in: text))
    #expect(SlashCommandInsertion.query(for: range, in: text) == "tab")
}

// MARK: Matching

@Test func anEmptyQueryOffersEverything() {
    #expect(SlashCommand.matching("") == SlashCommand.all)
}

@Test func namePrefixesRankAboveKeywordMatches() {
    let matches = SlashCommand.matching("ta")
    #expect(matches.first?.name == "Table", "expected Table first, got \(matches.first?.name ?? "none")")
}

@Test func keywordsFindThingsTheNameDoesNot() {
    #expect(SlashCommand.matching("mermaid").contains { $0.name == "Flowchart" })
    #expect(SlashCommand.matching("todo").contains { $0.name == "Task list" })
    #expect(SlashCommand.matching("latex").contains { $0.name == "Math block" })
    #expect(SlashCommand.matching("hr").contains { $0.name == "Divider" })
}

@Test func matchingIsCaseInsensitive() {
    #expect(SlashCommand.matching("TABLE").first?.name == "Table")
}

@Test func nonsenseMatchesNothing() {
    // A filter that keeps showing everything is not filtering.
    #expect(SlashCommand.matching("zzzzz").isEmpty)
}

// MARK: Insertion

/// Applies a command and returns the resulting document plus the caret.
private func insert(_ name: String, into text: String, caret: Int) -> (String, Int) {
    var document = source(text)
    let range = SlashCommandInsertion.activeToken(at: caret, in: document)!
    let command = SlashCommand.all.first { $0.name == name }!
    let result = SlashCommandInsertion.apply(command, replacing: range, in: document)
    document.apply(result.edit)
    return (document.text, result.caret)
}

@Test func insertingATableReplacesTheToken() {
    let (text, _) = insert("Table", into: "/tab", caret: 4)
    #expect(!text.contains("/tab"))
    #expect(text.hasPrefix("| Column | Column | Column |"))
    // Header, delimiter and two body rows.
    #expect(text.components(separatedBy: "\n").count == 4)
}

@Test func everySnippetLeavesTheCaretInsideIt() {
    for command in SlashCommand.all {
        let (text, caret) = insert(command.name, into: "/", caret: 1)
        #expect(caret >= 0 && caret <= text.utf8.count,
                "\(command.name) put the caret outside the document")
        #expect(!text.contains(String(SlashCommand.caretMarker)),
                "\(command.name) left its caret marker in the output")
    }
}

@Test func aBlockCommandPartwayThroughALineBreaksFirst() {
    // A table appended to the end of a sentence is not a table.
    let (text, _) = insert("Table", into: "Some text /tab", caret: 14)
    #expect(text.hasPrefix("Some text \n\n|"), "got <<<\(text.prefix(20))>>>")
}

@Test func anInlineCommandDoesNotBreakTheLine() {
    let (text, _) = insert("Link", into: "See /link", caret: 9)
    #expect(text == "See [](https://)")
}

@Test func aBlockCommandOnAnEmptyLineDoesNotAddBlankLines() {
    let (text, _) = insert("Quote", into: "first\n/quote", caret: 12)
    #expect(text == "first\n> ")
}

@Test func theCaretLandsWhereTheMarkerWas() {
    let (text, caret) = insert("Link", into: "/link", caret: 5)
    #expect(text == "[](https://)")
    // Between the brackets, which is where the label goes.
    #expect(caret == 1)
}

@Test func multibyteTextBeforeTheTokenDoesNotShiftTheCaret() {
    // Offsets are bytes, so an emoji ahead of the command must be counted as four.
    let (text, caret) = insert("Link", into: "👋 /link", caret: 10)
    #expect(text == "👋 [](https://)")
    #expect(caret == 6, "expected the caret just inside the brackets")
}

@Test func everySnippetParsesOnceThereIsTextInIt() {
    // Several snippets are deliberately empty: a heading is `# ` until you type a
    // title, and an empty heading is correctly nothing. So the test types at the
    // caret first, which is what the person who ran the command is about to do.
    for command in SlashCommand.all {
        var document = MarkdownSource("/")
        let range = SlashCommandInsertion.activeToken(at: 1, in: document)!
        let result = SlashCommandInsertion.apply(command, replacing: range, in: document)
        document.apply(result.edit)
        document.apply(TextEdit(byteRange: result.caret ..< result.caret, replacement: "Example"))

        let parsed = MarkdownParser.parse(document)
        #expect(!parsed.blocks.isEmpty, "\(command.name) produced nothing parseable")
        #expect(parsed.opaqueBlockCount == 0, "\(command.name) produced an unmappable block")
        #expect(!document.text.contains(String(SlashCommand.caretMarker)),
                "\(command.name) left its caret marker in the output")
    }
}

@Test func headingSnippetsProduceTheirLevel() {
    for (name, level) in [("Heading 1", 1), ("Heading 2", 2), ("Heading 3", 3)] {
        var document = MarkdownSource("/")
        let range = SlashCommandInsertion.activeToken(at: 1, in: document)!
        let command = SlashCommand.all.first { $0.name == name }!
        let result = SlashCommandInsertion.apply(command, replacing: range, in: document)
        document.apply(result.edit)
        document.apply(TextEdit(byteRange: result.caret ..< result.caret, replacement: "Title"))

        let parsed = MarkdownParser.parse(document)
        guard case .heading(let parsedLevel) = parsed.blocks.first?.kind else {
            Issue.record("\(name) did not produce a heading"); continue
        }
        #expect(parsedLevel == level)
    }
}

@Test func theDiagramSnippetsActuallyParseAsDiagrams() throws {
    for name in ["Flowchart", "Sequence diagram"] {
        let (text, _) = insert(name, into: "/", caret: 1)
        let parsed = MarkdownParser.parse(MarkdownSource(text))
        guard case .mermaid(let diagram) = parsed.blocks.first?.kind else {
            Issue.record("\(name) did not produce a mermaid block"); continue
        }
        // And the Mermaid inside it has to parse too, or the snippet inserts a
        // diagram that immediately shows an error.
        #expect(throws: Never.self) { try MermaidParser.parse(diagram) }
    }
}

@Test func theTableSnippetParsesAsATableWithThreeColumns() throws {
    let (text, _) = insert("Table", into: "/", caret: 1)
    let parsed = MarkdownParser.parse(MarkdownSource(text))
    guard case .table(let model) = parsed.blocks.first?.kind else {
        Issue.record("the table snippet did not parse as a table"); return
    }
    #expect(model.columns.count == 3)
    #expect(model.rows.count == 2)
}
