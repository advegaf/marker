import Testing
import Foundation
@testable import MarkerCore

/// A budget, not a benchmark.
///
/// This exists because the editing design turns on one number: whether the whole
/// document can be reparsed on every keystroke. The first measurement said 100 ms
/// for a 367 KB file, which would have meant building four tiers of incremental
/// reparse. The cost turned out to be `slice` rebuilding the UTF-8 array on every
/// inline run, making lowering quadratic. With the bytes held once it is linear,
/// and the tiers are not needed.
@Test func fullReparseStaysWithinItsBudget() throws {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent()

    // Budgets are generous on purpose. This runs on whatever machine happens to be
    // building, often alongside a compile, so the point is to catch a return to
    // quadratic behaviour rather than to police a few milliseconds. The fastest of
    // several runs is used, which is the least noisy statistic available here.
    for (name, budget) in [("kitchen-sink.md", 0.020), ("long.md", 0.150)] {
        let text = try String(contentsOf: root.appendingPathComponent("QA/fixtures/\(name)"), encoding: .utf8)
        let source = MarkdownSource(text)
        _ = MarkdownParser.parse(source)

        var fastest = Double.greatestFiniteMagnitude
        for _ in 0 ..< 5 {
            let start = Date()
            _ = MarkdownParser.parse(source)
            fastest = min(fastest, Date().timeIntervalSince(start))
        }

        print(String(format: "[perf] %@ %d bytes: parse %.1f ms", name, source.byteCount, fastest * 1000))
        #expect(fastest < budget, "\(name) parsed in \(Int(fastest * 1000)) ms, budget \(Int(budget * 1000)) ms")
    }
}

/// Guards the specific mistake: `slice` must not be linear in document size.
@Test func slicingIsIndependentOfDocumentSize() {
    func timeSlices(_ size: Int) -> TimeInterval {
        let source = MarkdownSource(String(repeating: "a", count: size))
        let start = Date()
        for index in 0 ..< 2_000 {
            _ = source.slice(index ..< (index + 4))
        }
        return Date().timeIntervalSince(start)
    }

    let small = timeSlices(10_000)
    let large = timeSlices(400_000)
    // Forty times the document, and slicing must not be meaningfully slower. A
    // generous factor, since this is guarding against quadratic, not against noise.
    #expect(large < small * 8 + 0.05, "slicing scales with document size: \(small) then \(large)")
}
