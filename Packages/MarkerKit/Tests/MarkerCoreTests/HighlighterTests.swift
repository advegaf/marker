import Testing
@testable import MarkerCore

// The property that makes the whole design safe: concatenating a token's text
// reproduces the input exactly. If that ever breaks, highlighting silently
// corrupts what the reader sees, so it is checked for every language before any
// assertion about colours.

private func kinds(_ code: String, _ language: String) -> [TokenKind] {
    Highlighter.tokenize(code, language: language).map(\.kind)
}

private func assertLossless(_ code: String, _ language: String, _ label: String = "") {
    let joined = Highlighter.tokenize(code, language: language).map(\.text).joined()
    #expect(joined == code, "\(language) \(label) lost or altered text")
}

/// The token holding `needle` must have this kind.
private func assertToken(_ code: String, _ language: String, _ needle: String, is kind: TokenKind) {
    let tokens = Highlighter.tokenize(code, language: language)
    let match = tokens.first { $0.text.contains(needle) }
    #expect(match?.kind == kind,
            "\(language): <<<\(needle)>>> was \(match?.kind.rawValue ?? "missing"), expected \(kind.rawValue)")
}

@Test func everyLanguageRoundTripsItsSample() {
    for (language, sample) in Samples.all {
        assertLossless(sample, language)
    }
}

@Test func everyRuleIsReachableByEveryAliasItClaims() {
    for rule in LanguageRule.all {
        for name in rule.names {
            #expect(LanguageRule.named(name) != nil, "alias \(name) resolves to nothing")
            #expect(LanguageRule.named(name.uppercased()) != nil, "alias \(name) is case sensitive")
        }
    }
}

@Test func unknownLanguagesRenderAsOnePlainToken() {
    let tokens = Highlighter.tokenize("some brainfuck here", language: "brainfuck")
    #expect(tokens.map(\.kind) == [.plain])
    #expect(Highlighter.supports("brainfuck") == false)
}

@Test func emptyInputProducesNoTokens() {
    #expect(Highlighter.tokenize("", language: "swift").isEmpty)
    #expect(Highlighter.tokenize("", language: nil).isEmpty)
}

@Test func nilLanguageIsNotHighlighted() {
    let tokens = Highlighter.tokenize("let x = 1", language: nil)
    #expect(tokens.map(\.kind) == [.plain])
}

// MARK: Per language

@Test func swiftHighlightsKeywordsTypesStringsAndAttributes() {
    let code = #"@MainActor func greet() -> String { return "hi" } // done"#
    assertLossless(code, "swift")
    assertToken(code, "swift", "@MainActor", is: .attribute)
    assertToken(code, "swift", "func", is: .keyword)
    assertToken(code, "swift", "String", is: .type)
    assertToken(code, "swift", "\"hi\"", is: .string)
    assertToken(code, "swift", "// done", is: .comment)
}

@Test func swiftTripleQuotedStringsDoNotSwallowTheFile() {
    let code = "let a = \"\"\"\nmulti \"line\"\n\"\"\"\nlet b = 1\n"
    assertLossless(code, "swift")
    assertToken(code, "swift", "multi", is: .string)
    // The code after the closing fence is still scanned.
    #expect(kinds(code, "swift").contains(.number))
}

@Test func pythonHighlightsDecoratorsAndLiterals() {
    let code = "@cache\ndef f(x: int = 3) -> bool:\n    return True  # ok\n"
    assertLossless(code, "python")
    assertToken(code, "python", "@cache", is: .attribute)
    assertToken(code, "python", "def", is: .keyword)
    assertToken(code, "python", "True", is: .number)
    assertToken(code, "python", "# ok", is: .comment)
}

@Test func javascriptHandlesTemplateLiteralsAndBlockComments() {
    let code = "/* note */ const url = `a/${b}/c`; let n = 0x1F;"
    assertLossless(code, "javascript")
    assertToken(code, "javascript", "/* note */", is: .comment)
    assertToken(code, "javascript", "const", is: .keyword)
    assertToken(code, "javascript", "`a/", is: .string)
    assertToken(code, "javascript", "0x1F", is: .number)
}

@Test func rustHighlightsAttributesAndPrimitiveTypes() {
    let code = "#[derive(Debug)]\npub fn add(a: u32, b: u32) -> u32 { a + b }"
    assertLossless(code, "rust")
    assertToken(code, "rust", "#[derive", is: .attribute)
    assertToken(code, "rust", "pub", is: .keyword)
    assertToken(code, "rust", "u32", is: .type)
}

@Test func goHighlightsBacktickStringsAndBuiltinTypes() {
    let code = "func main() {\n\ts := `raw string`\n\tvar n int64 = 7\n}"
    assertLossless(code, "go")
    assertToken(code, "go", "func", is: .keyword)
    assertToken(code, "go", "`raw string`", is: .string)
    assertToken(code, "go", "int64", is: .type)
}

@Test func shellHighlightsVariablesAndComments() {
    let code = "#!/bin/bash\nset -euo pipefail\ncd $HOME  # home\n"
    assertLossless(code, "bash")
    assertToken(code, "bash", "set", is: .keyword)
    assertToken(code, "bash", "$HOME", is: .attribute)
    // A variable inside a string stays part of the string. Shells do interpolate
    // there, but colouring inside string literals is a refinement, not a promise.
    assertLossless("echo \"$HOME\"\n", "bash")
}

@Test func sqlIsCaseInsensitiveOnKeywords() {
    assertLossless("select * from users where id = 1;", "sql")
    assertToken("SELECT * FROM t;", "sql", "SELECT", is: .keyword)
    assertToken("select * from t;", "sql", "select", is: .keyword)
}

@Test func cAndFriendsShareOneRule() {
    let code = "#include <stdio.h>\nint main(void) { /* go */ return 0; }"
    assertLossless(code, "c")
    assertLossless(code, "cpp")
    assertToken(code, "c", "#include", is: .attribute)
    assertToken(code, "c", "int", is: .type)
}

@Test func htmlHighlightsTagsAttributesAndComments() {
    let code = "<!-- hi -->\n<a href=\"/x\" class='y'>text</a>\n"
    assertLossless(code, "html")
    assertToken(code, "html", "<!-- hi -->", is: .comment)
    assertToken(code, "html", "href", is: .attribute)
    assertToken(code, "html", "\"/x\"", is: .string)
}

@Test func yamlHighlightsKeysCommentsAndScalars() {
    let code = "# config\nname: marker\nversion: 2\nenabled: true\nlist:\n  - one\n  - two\n"
    assertLossless(code, "yaml")
    assertToken(code, "yaml", "# config", is: .comment)
    assertToken(code, "yaml", "name", is: .attribute)
    assertToken(code, "yaml", "true", is: .keyword)
}

@Test func yamlPreservesIndentationExactly() {
    // Reindenting YAML would change its meaning, so the scanner must never touch it.
    let code = "a:\n  b:\n    c: 1\n\td: 2\n"
    assertLossless(code, "yaml")
}

@Test func javaAndKotlinShareOneRule() {
    let code = "@Override\npublic String name() { return \"x\"; }"
    assertLossless(code, "java")
    assertLossless(code, "kotlin")
    assertToken(code, "java", "@Override", is: .attribute)
    assertToken(code, "java", "public", is: .keyword)
}

@Test func rubyAndCssTokenize() {
    assertLossless("class Foo\n  def bar; @x = 1; end\nend\n", "ruby")
    assertToken("class Foo", "ruby", "class", is: .keyword)
    assertLossless(".a { color: #fff; /* c */ }\n@media screen {}\n", "css")
    assertToken("@media screen {}", "css", "@media", is: .attribute)
}

@Test func unterminatedConstructsDoNotEatTheRestOfTheFile() {
    // What a half typed line looks like. The scanner must still terminate and must
    // still return every character.
    assertLossless("let s = \"unterminated\nlet t = 1\n", "swift", "unterminated string")
    assertLossless("/* unterminated comment\nstill here", "swift", "unterminated comment")
    assertLossless("<div class=\"x", "html", "unterminated tag")
    assertLossless("@", "swift", "bare attribute prefix")
}

private enum Samples {
    static let all: [(String, String)] = [
        ("swift", "@MainActor final class A: B {\n  let x: Int = 0x1F  // c\n}\n"),
        ("javascript", "export const f = async () => `t${1}`; /* b */\n"),
        ("python", "@dec\nclass A:\n  '''doc'''\n  x = None\n"),
        ("rust", "#[test]\nfn t() { let v: Vec<u8> = vec![]; }\n"),
        ("go", "package main\nimport \"fmt\"\nfunc main() { fmt.Println(`x`) }\n"),
        ("c", "#define X 1\nstatic int f(char *s) { return 0; }\n"),
        ("java", "@Test public void t() throws Exception { }\n"),
        ("ruby", "module M\n  def self.x; @@y ||= 1; end\nend\n"),
        ("bash", "for f in *.md; do echo \"${f}\"; done\n"),
        ("sql", "SELECT a, b FROM t WHERE c = 'x' -- note\n"),
        ("css", ":root { --a: 1px; }\n.b::after { content: \"x\"; }\n"),
        ("html", "<ul>\n  <li data-x=\"1\">a &amp; b</li>\n</ul>\n"),
        ("yaml", "a: 1\nb:\n  - c\n  - d: \"e\"  # f\n"),
        ("json", "{\"a\": [1, true, null], \"b\": \"c\"}\n"),
    ]
}
