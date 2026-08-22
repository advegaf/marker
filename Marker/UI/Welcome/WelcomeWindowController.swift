import AppKit
import SwiftUI

/// The first-launch walkthrough.
///
/// It is one panel rather than a paged carousel, because the walkthrough that
/// actually teaches this app is the app rendering a document. Four lines name what
/// Marker does, and the button hands the reader a real Markdown file open in a real
/// Marker window. Everything after that is the product explaining itself.
final class WelcomeWindowController: NSWindowController {

    static let shared = WelcomeWindowController()

    private init() {
        let hosting = NSHostingController(rootView: WelcomeView())
        let window = NSWindow(contentViewController: hosting)
        // No title text and no toolbar: the content is the whole composition, and a
        // title bar reading "Welcome" above a heading reading "Marker" says the same
        // thing twice. The traffic lights stay, so the window is still closable the
        // way every other window on the system is.
        // Titled for the Window menu and for VoiceOver, even though the title bar
        // does not draw it. An untitled window reads as "Untitled" in both.
        window.title = "Welcome to Marker"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.isMovableByWindowBackground = true
        window.isRestorable = false
        // Pin the width, lay out, then measure. Reading `fittingSize` straight off
        // a fresh hosting view measures it at whatever width AppKit happens to
        // have given it, which is narrower than the design: every row wrapped to
        // two lines, the height came back inflated, and the panel sat in a window
        // with dead space beneath it.
        hosting.view.setFrameSize(NSSize(width: WelcomeView.width, height: 0))
        hosting.view.layoutSubtreeIfNeeded()
        window.setContentSize(hosting.view.fittingSize)
        window.center()
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("unavailable") }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        window?.makeKeyAndOrderFront(sender)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Whether to show it at launch.
    ///
    /// Order matters. `MARKER_WELCOME` is itself a `MARKER_` variable, so it would
    /// satisfy `Harness.isActive` and be suppressed by its own guard if the harness
    /// check came first. Explicit request wins, then the harness, then the stored
    /// key. Without the harness case in the middle, every snapshot run would capture
    /// this window sitting in front of the document it was meant to shoot.
    static var shouldShowAtLaunch: Bool {
        if ProcessInfo.processInfo.environment["MARKER_WELCOME"] != nil { return true }
        if Harness.isActive { return false }
        return !Preferences.hasSeenWelcome
    }
}

// MARK: - The view

private struct WelcomeView: View {

    /// The design width. The controller needs it too, to measure the height at the
    /// width the layout is actually built for.
    static let width: CGFloat = 520

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    private struct Feature: Identifiable {
        let id = UUID()
        let symbol: String
        let text: String
    }

    /// Four claims, each one a thing the reader can go and do straight away. No
    /// dashes in any of it: the guard suite fails the build on an em or en dash in
    /// a string literal.
    private let features = [
        Feature(symbol: "magnifyingglass",
                text: "Find with Command F. Every match stays highlighted."),
        Feature(symbol: "arrow.up.left.and.arrow.down.right",
                text: "Pinch to zoom around your pointer. Text stays sharp."),
        // `eye` rather than `space`: the space bar glyph is a thin bracket that
        // reads as a stray dash next to three solid symbols, and the idea here is
        // previewing, not the key that does it.
        Feature(symbol: "eye",
                text: "Press space on a Markdown file in Finder to preview it."),
        Feature(symbol: "square.and.pencil",
                text: "Edit the page. It saves clean Markdown to the same file."),
    ]

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.top, 34)
                .padding(.bottom, 26)

            VStack(alignment: .leading, spacing: 14) {
                ForEach(Array(features.enumerated()), id: \.element.id) { index, feature in
                    row(feature)
                        .opacity(appeared ? 1 : 0)
                        .offset(y: appeared ? 0 : 8)
                        .animation(
                            MarkerMotion.settle(
                                MarkerMotion.micro.delay(Double(index) * MarkerMotion.stagger),
                                reduceMotion: reduceMotion
                            ),
                            value: appeared
                        )
                }
            }
            .padding(.horizontal, 40)

            footer
                .padding(.top, 30)
                .padding(.bottom, 26)
        }
        .frame(width: Self.width)
        .onAppear { appeared = true }
    }

    private var header: some View {
        VStack(spacing: 10) {
            if let icon = NSApp.applicationIconImage {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 76, height: 76)
                    .accessibilityHidden(true)
            }
            Text("Marker")
                .font(.system(size: 26, weight: .semibold))
            Text("Version \(Self.version)")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        // The header carries the whole entrance; the rows stagger in behind it.
        .opacity(appeared ? 1 : 0)
        .animation(
            MarkerMotion.settle(MarkerMotion.signature, reduceMotion: reduceMotion),
            value: appeared
        )
    }

    private func row(_ feature: Feature) -> some View {
        HStack(alignment: .top, spacing: 14) {
            // A fixed-width symbol column, so four glyphs of different widths still
            // leave their text on one optical margin.
            Image(systemName: feature.symbol)
                .font(.system(size: 16))
                .foregroundStyle(.tint)
                .frame(width: 24, alignment: .center)
                .accessibilityHidden(true)
            Text(feature.text)
                .font(.callout)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    private var footer: some View {
        VStack(spacing: 12) {
            Button("Open the welcome document") {
                WelcomeDocument.open()
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)

            Button("Skip for now") { dismiss() }
                .buttonStyle(.link)
                .font(.callout)
                .keyboardShortcut(.cancelAction)
        }
        .opacity(appeared ? 1 : 0)
        .animation(
            MarkerMotion.settle(
                MarkerMotion.micro.delay(Double(features.count) * MarkerMotion.stagger),
                reduceMotion: reduceMotion
            ),
            value: appeared
        )
    }

    /// Either button counts as having seen it. Closing the window with the red
    /// button does too, which is handled where the window is presented.
    private func dismiss() {
        Preferences.hasSeenWelcome = true
        WelcomeWindowController.shared.close()
    }

    private static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }
}
