import Testing
import Foundation

// Source-scanning rules, in the shape minus/MinusTests/DesignGuardTests.swift uses:
// deliberately dumb substring scans over raw file text, so a violation is caught
// even in a file that does not currently compile.
//
// These live in the package rather than the app-hosted bundle. They only read
// files, so an app host buys nothing, and running them under one hung the test
// host inside FileManager.enumerator. In the package they run in milliseconds.

private enum Scan {

    /// This file sits at <repoRoot>/Packages/MarkerKit/Tests/MarkerCoreTests/.
    static let repoRoot: URL = {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0 ..< 5 { url = url.deletingLastPathComponent() }
        return url
    }()

    static let roots = ["Marker", "MarkerQuickLook", "Packages/MarkerKit/Sources"]

    struct Violation {
        let path: String
        let line: Int
        let text: String
    }

    /// Explicit recursion over `contentsOfDirectory` rather than a
    /// `DirectoryEnumerator`, so the walk is bounded and obvious.
    static func swiftFiles() -> [URL] {
        var found: [URL] = []
        for root in roots {
            collect(URL(fileURLWithPath: root, relativeTo: repoRoot), into: &found)
        }
        return found
    }

    private static func collect(_ directory: URL, into found: inout [URL]) {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        for url in contents {
            let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            if isDirectory {
                collect(url, into: &found)
            } else if url.pathExtension == "swift" {
                found.append(url)
            }
        }
    }

    static func violations(matching patterns: [String]) -> [Violation] {
        var found: [Violation] = []
        for file in swiftFiles() {
            guard let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
            for (offset, line) in text.components(separatedBy: .newlines).enumerated() {
                for pattern in patterns where line.contains(pattern) {
                    found.append(Violation(
                        path: file.path.replacingOccurrences(of: repoRoot.path + "/", with: ""),
                        line: offset + 1,
                        text: line.trimmingCharacters(in: .whitespaces)
                    ))
                }
            }
        }
        return found
    }

    static func report(_ violations: [Violation]) -> String {
        violations.map { "  \($0.path):\($0.line): \($0.text)" }.joined(separator: "\n")
    }
}

@Test func sourceTreeIsActuallyBeingScanned() {
    // A scan that silently finds no files would make every rule below pass
    // vacuously, which is worse than having no rule at all.
    #expect(Scan.swiftFiles().count > 10)
}

/// The product's headline claim is a native engine with no WebView. That is a
/// permanent property of the binary, so it gets a test rather than a promise.
@Test func noWebViewOrJavaScriptAnywhere() {
    let hits = Scan.violations(matching: ["WKWebView", "import WebKit", "JavaScriptCore"])
    #expect(hits.isEmpty, """
    Rule 1 (no WebView): WKWebView, WebKit and JavaScriptCore must not appear in the app,
    the extension, or MarkerKit. No exceptions.
    \(Scan.report(hits))
    """)
}

/// The user's standing writing rule, enforced the way vita enforces it.
@Test func noEmOrEnDashesInSource() {
    let hits = Scan.violations(matching: ["\u{2014}", "\u{2013}"])
    #expect(hits.isEmpty, """
    Rule 2 (no dashes): em dashes and en dashes are banned in source, comments included.
    \(Scan.report(hits))
    """)
}

/// Colours belong to the theme. A literal NSColor outside it is a colour that no
/// longer responds to the appearance switch.
@Test func coloursAreDefinedOnlyInTheThemeFile() {
    let hits = Scan.violations(matching: ["NSColor(srgbRed", "NSColor(calibratedRed", "NSColor(red:"])
        .filter { !$0.path.hasSuffix("MarkerRender/MarkerTheme.swift") }
    #expect(hits.isEmpty, """
    Rule 3 (theme containment): literal colours may only appear in MarkerTheme.swift.
    \(Scan.report(hits))
    """)
}
