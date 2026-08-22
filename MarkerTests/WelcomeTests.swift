import XCTest
@testable import Marker

/// The walkthrough's two silent failure modes.
///
/// Both of these fail as "nothing happens" at runtime: a missing bundle resource
/// beeps, and a welcome window that reappears every launch is a bug nobody reports
/// because it looks intentional.
nonisolated final class WelcomeTests: XCTestCase {


    func testTheWelcomeDocumentIsBundled() {
        // If the Resources glob ever stops picking this up, the button on the
        // walkthrough beeps and does nothing, which is the worst first impression
        // the app can make.
        let url = Bundle.main.url(forResource: "Welcome to Marker", withExtension: "md")
        XCTAssertNotNil(url, "Welcome to Marker.md is not in the app bundle")
    }

    func testTheBundledDocumentParsesAsTheFeaturesItAdvertises() throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "Welcome to Marker", withExtension: "md"))
        let text = try String(contentsOf: url, encoding: .utf8)
        // The document is the walkthrough. If a fence goes missing the reader is
        // told about a feature and then shown nothing.
        XCTAssertTrue(text.contains("```mermaid"), "no diagram to demonstrate")
        XCTAssertTrue(text.contains("```swift"), "no highlighted code to demonstrate")
        XCTAssertTrue(text.contains("$$"), "no display math to demonstrate")
        XCTAssertTrue(text.contains("| What |"), "no table to demonstrate")
        XCTAssertTrue(text.contains("- [x]"), "no task list to demonstrate")
    }

    @MainActor
    func testTheWalkthroughIsShownOnceAndThenNeverAgain() {
        UserDefaults.standard.removeObject(forKey: Preferences.welcomeKey)
        defer { UserDefaults.standard.removeObject(forKey: Preferences.welcomeKey) }

        XCTAssertFalse(Preferences.hasSeenWelcome)
        Preferences.hasSeenWelcome = true
        XCTAssertTrue(Preferences.hasSeenWelcome)
    }

    @MainActor
    func testAnyMarkerVariableArmsTheHarness() {
        // The walkthrough is suppressed by Harness.isActive, so the rule that any
        // MARKER_ prefixed variable arms it is what keeps a snapshot run from
        // capturing a welcome window instead of the document it asked for.
        let armed = !ProcessInfo.processInfo.environment.keys
            .filter { $0.hasPrefix("MARKER_") }.isEmpty
        XCTAssertEqual(Harness.isActive, armed)
    }

    @MainActor
    func testTheDocumentIsCopiedOutOfTheBundleBeforeItIsOpened() throws {
        // Opening the bundle copy in place would mean the first save either fails
        // on permissions or succeeds and breaks the code signature. Editing is
        // free, so this is a likely first move, not an edge case.
        let target = WelcomeDocument.destination
        try? FileManager.default.removeItem(at: target)

        let url = try XCTUnwrap(WelcomeDocument.materialize())
        XCTAssertEqual(url, target)
        XCTAssertTrue(FileManager.default.fileExists(atPath: target.path))
        XCTAssertFalse(url.path.contains(".app/Contents/Resources"), "opened the bundle copy in place")
        XCTAssertTrue(FileManager.default.isWritableFile(atPath: target.path))

        // A second call must not overwrite: someone who edited it and came back
        // through the Help menu should find their own version.
        try "edited".write(to: target, atomically: true, encoding: .utf8)
        _ = WelcomeDocument.materialize()
        XCTAssertEqual(try String(contentsOf: target, encoding: .utf8), "edited")

        try? FileManager.default.removeItem(at: target)
    }

    func testTheCopyCarriesNoDashes() {
        // The guard suite covers source under Marker/, but the welcome document is
        // a resource and would slip past it.
        let url = Bundle.main.url(forResource: "Welcome to Marker", withExtension: "md")
        let text = (try? String(contentsOf: XCTUnwrap(url), encoding: .utf8)) ?? ""
        XCTAssertFalse(text.contains("\u{2014}"), "em dash in the welcome document")
        XCTAssertFalse(text.contains("\u{2013}"), "en dash in the welcome document")
    }
}
