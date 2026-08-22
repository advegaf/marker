import AppKit
import MarkerCore
import MarkerRender

/// Hosts the document surface: a scroll view over one TextKit 2 text view.
final class DocumentViewController: NSViewController {

    private unowned let document: MarkerDocument
    private var scrollView: NSScrollView!
    private var textView: MarkdownTextView!

    private let zoom = ZoomController()

    private var theme: MarkerTheme {
        MarkerApp.appearance.theme(zoom: zoom.scale)
    }

    init(document: MarkerDocument) {
        self.document = document
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("unavailable") }

    override func loadView() {
        let theme = self.theme
        textView = MarkdownTextView(theme: theme)

        scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 900, height: 700))
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = true
        scrollView.backgroundColor = theme.colors.background
        scrollView.documentView = textView
        // Pinch already centres on the gesture location, which is the pointer, so
        // "zoom around your pointer" is the platform behaviour. The commit-to-point-size
        // step that keeps text crisp above 1.5x arrives with ZoomController.
        scrollView.allowsMagnification = true
        scrollView.minMagnification = 0.5
        scrollView.maxMagnification = 3.0

        view = scrollView
        render()

        // Fold a finished pinch into the zoom factor and re-render at real point
        // sizes, rather than leaving the scroll view scaling a rasterised layer.
        NotificationCenter.default.addObserver(
            self, selector: #selector(liveMagnifyDidEnd),
            name: NSScrollView.didEndLiveMagnifyNotification, object: scrollView
        )

        NotificationCenter.default.addObserver(
            self, selector: #selector(appearanceDidChange),
            name: .markerAppearanceDidChange, object: nil
        )
    }

    @objc private func appearanceDidChange() {
        scrollView.backgroundColor = theme.colors.background
        render()
    }

    // MARK: Scrolling

    /// Used by the QA harness to prove scrolling actually reaches the end of a long
    /// document, which is the one thing a top-of-document screenshot cannot show.
    func scroll(to edge: ScrollEdge) {
        // NSTextView's own responder actions, which is what ⌘↓ and ⌘↑ invoke. Moving
        // the clip view directly gets the offset right but leaves TextKit 2's
        // viewport layout controller pointing at the old region, so the page draws
        // blank at the new position. Going through the text view updates both.
        switch edge {
        case .top: textView.scrollToBeginningOfDocument(nil)
        case .bottom: textView.scrollToEndOfDocument(nil)
        }
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    enum ScrollEdge: String { case top, bottom }

    /// Frame height, visible height and current offset, for the harness to report.
    var scrollMetrics: (document: CGFloat, visible: CGFloat, offset: CGFloat) {
        (textView.frame.height, scrollView.contentSize.height, scrollView.contentView.bounds.origin.y)
    }

    /// Extra numbers for the harness, so a wrong height can be traced to the source,
    /// the attributed string, or the layout rather than guessed at.
    var diagnostics: String {
        var fragments = 0
        var bottom: CGFloat = 0
        if let lm = textView.textLayoutManager {
            lm.enumerateTextLayoutFragments(from: lm.documentRange.location, options: [.ensuresLayout]) {
                fragments += 1
                bottom = max(bottom, $0.layoutFragmentFrame.maxY)
                return true
            }
        }
        return "bytes=\(document.source.byteCount) attrLen=\(textView.textStorage?.length ?? -1) fragments=\(fragments) bottom=\(Int(bottom))"
    }

    // MARK: Zoom

    @objc func zoomIn(_ sender: Any?) { applyZoom(zoom.stepUp()) }
    @objc func zoomOut(_ sender: Any?) { applyZoom(zoom.stepDown()) }
    @objc func resetZoom(_ sender: Any?) { applyZoom(zoom.reset()) }

    @objc private func liveMagnifyDidEnd(_ note: Notification) {
        let gesture = scrollView.magnification
        guard abs(gesture - 1.0) > 0.001 else { return }
        scrollView.magnification = 1.0
        applyZoom(zoom.fold(gesture: gesture))
    }

    /// Re-render at the new point size. Text stays crisp at any scale and reflows
    /// to the window width instead of growing a horizontal scrollbar.
    private func applyZoom(_ changed: Bool) {
        guard changed else { return }
        render()
    }

    private func render() {
        let theme = self.theme
        let width = max(scrollView.contentSize.width, 320)
        let rendered = DocumentRenderer(theme: theme, mode: .interactive).render(document.source)
        textView.setContent(rendered, theme: theme, availableWidth: width)
    }

    /// The measure is computed against a width, and `applyMeasure` deliberately
    /// stops the container from tracking the view, so a resize has to re-run it.
    /// Guarded on the width actually changing, since layout runs constantly.
    override func viewDidLayout() {
        super.viewDidLayout()
        let width = max(scrollView.contentSize.width, 320)
        if abs(width - textView.measuredWidth) > 0.5 {
            // Real width change: the measure has to be recomputed and recentred.
            textView.apply(theme: theme, availableWidth: width)
        } else {
            // Same width, but re-assert the height. The first layout pass runs before
            // the view is in a window, and TextKit 2 can report a short usage bound
            // then, so the authoritative height is the one computed once it is.
            textView.sizeToFitContent(theme: theme, availableWidth: width)
        }
    }
}
