import Testing
import Foundation
@testable import MarkerCore

// The printer only ever moves whitespace between tokens. These tests hold it to
// that, because the failure mode of a formatter is silently rewriting someone's
// file into something that no longer means the same thing.

/// Strips whitespace that sits outside string literals, which is exactly what the
/// printer is allowed to change.
private func structure(_ json: String) -> String {
    var output = ""
    var inString = false
    var escaping = false
    for character in json {
        if escaping { output.append(character); escaping = false; continue }
        if inString {
            output.append(character)
            if character == "\\" { escaping = true }
            if character == "\"" { inString = false }
            continue
        }
        if character == "\"" { inString = true; output.append(character); continue }
        if character.isWhitespace { continue }
        output.append(character)
    }
    return output
}

@Test func prettyPrintingChangesOnlyWhitespace() {
    let minified = #"{"name":"marker","tags":["a","b"],"meta":{"n":1,"ok":true},"none":null}"#
    let pretty = JSONPrettyPrinter.prettyPrinted(minified)
    #expect(pretty != minified, "nothing was reformatted")
    #expect(structure(pretty) == structure(minified), "the printer altered more than whitespace")
}

@Test func keyOrderIsPreserved() {
    // JSONSerialization would return these alphabetised, which makes a diff against
    // the original file useless. That is why this is not built on it.
    let json = #"{"zebra":1,"apple":2,"mango":3}"#
    let pretty = JSONPrettyPrinter.prettyPrinted(json)
    let zebra = pretty.range(of: "zebra")!.lowerBound
    let apple = pretty.range(of: "apple")!.lowerBound
    let mango = pretty.range(of: "mango")!.lowerBound
    #expect(zebra < apple)
    #expect(apple < mango)
}

@Test func stringsPassThroughUntouched() {
    // Braces, colons and newline escapes inside a string must not be read as
    // structure, or the output is reindented against imaginary nesting.
    let json = #"{"tricky":"a{b}c:d,e","escaped":"quote \" and \\ backslash","nl":"x\ny"}"#
    let pretty = JSONPrettyPrinter.prettyPrinted(json)
    #expect(pretty.contains(#""a{b}c:d,e""#))
    #expect(pretty.contains(#""quote \" and \\ backslash""#))
    #expect(pretty.contains(#""x\ny""#))
}

@Test func emptyContainersStayOnOneLine() {
    let pretty = JSONPrettyPrinter.prettyPrinted(#"{"a":{},"b":[],"c":[{}]}"#)
    #expect(pretty.contains("{}"))
    #expect(pretty.contains("[]"))
    #expect(!pretty.contains("{\n\n"))
}

@Test func invalidJSONIsReturnedUnchanged() {
    // A viewer that mangles a file it could not parse is worse than one that shows
    // the file as it is.
    for broken in [#"{"a": "#, #"{"a": 1]"#, #"{"unterminated: 1}"#, "not json at all", ""] {
        #expect(JSONPrettyPrinter.prettyPrinted(broken) == broken, "mangled <<<\(broken)>>>")
    }
}

@Test func alreadyPrettyJSONStaysStable() {
    // Running it twice must not keep changing the file, or saving would churn.
    let once = JSONPrettyPrinter.prettyPrinted(#"{"a":[1,2],"b":{"c":"d"}}"#)
    let twice = JSONPrettyPrinter.prettyPrinted(once)
    #expect(once == twice)
}

@Test func outputParsesBackToTheSameValue() throws {
    let original = #"{"n":[1,2,{"deep":[true,false,null]}],"s":"x","f":1.5}"#
    let pretty = JSONPrettyPrinter.prettyPrinted(original)
    let a = try JSONSerialization.jsonObject(with: Data(original.utf8)) as? NSDictionary
    let b = try JSONSerialization.jsonObject(with: Data(pretty.utf8)) as? NSDictionary
    #expect(a == b, "the reformatted document no longer parses to the same value")
}

@Test func nestingIsIndentedByDepth() {
    let pretty = JSONPrettyPrinter.prettyPrinted(#"{"a":{"b":{"c":1}}}"#)
    let lines = pretty.components(separatedBy: "\n")
    let deepest = try? #require(lines.first { $0.contains("\"c\"") })
    #expect(deepest?.hasPrefix("      ") == true, "expected three levels of indent, got <<<\(deepest ?? "")>>>")
}
