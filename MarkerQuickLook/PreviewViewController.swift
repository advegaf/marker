import AppKit
import Quartz
import MarkerCore
import MarkerRender

/// Quick Look preview: what you get when you press space on a markdown file.
///
/// Renders through the same engine as the app, in `.image` mode, so no attachment
/// views are ever instantiated inside the extension.
final class PreviewViewController: NSViewController, QLPreviewingController {

    private var scrollView: NSScrollView!
    private var textView: MarkdownTextView!
    private var source = MarkdownSource("")

    /// The extension is sandboxed and cannot read the app's theme preference
    /// without an app group, so the preview follows the system appearance. That is
    /// a known limitation rather than a defect, and the CSV records it as one.
    private var theme: MarkerTheme {
        let isDark = view.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        return .standard(isDark ? .dark : .light)
    }

    override func loadView() {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))

        scrollView = NSScrollView(frame: container.bounds)
        scrollView.autoresizingMask = [.width, .height]
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = true

        textView = MarkdownTextView(theme: .standard(.light))
        scrollView.documentView = textView

        container.addSubview(scrollView)
        view = container
        // Without this the Quick Look host picks an arbitrary frame for the preview.
        preferredContentSize = NSSize(width: 820, height: 620)
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        let width = max(scrollView.contentSize.width, 320)
        guard abs(width - textView.measuredWidth) > 0.5 else { return }
        render(width: width)
    }

    func preparePreviewOfFile(at url: URL) async throws {
        let data = try Data(contentsOf: url)
        guard let text = Self.decode(data) else {
            throw CocoaError(.fileReadInapplicableStringEncoding)
        }
        source = MarkdownSource(text)
        render(width: max(scrollView.contentSize.width, 320))
    }

    private func render(width: CGFloat) {
        let theme = self.theme
        scrollView.backgroundColor = theme.colors.background
        let rendered = DocumentRenderer(theme: theme, mode: .image).render(source)
        // setContent, not setAttributedString: it also forces full layout and sizes
        // the frame, which is what lets the preview scroll to the end of the file.
        textView.setContent(rendered, theme: theme, availableWidth: width)
    }

    /// Files in the wild are not all UTF-8, and a preview that refuses to render is
    /// worse than one that guesses an encoding.
    private static func decode(_ data: Data) -> String? {
        if let utf8 = String(data: data, encoding: .utf8) { return utf8 }
        for encoding: String.Encoding in [.utf16, .isoLatin1, .macOSRoman] {
            if let text = String(data: data, encoding: encoding) { return text }
        }
        return nil
    }
}
