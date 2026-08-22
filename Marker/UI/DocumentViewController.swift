import AppKit
import MarkerCore
import MarkerRender

/// Hosts the document surface: a scroll view over one TextKit 2 text view.
final class DocumentViewController: NSViewController {

    /// Reading is the default and nothing enters editing on its own. The product is
    /// a viewer first, so the caret has to be asked for.
    enum EditMode { case reading, editing }

    private(set) var editMode: EditMode = .reading

    /// Lets the window controller keep the toolbar's Edit button in step without the
    /// view controller knowing the toolbar exists.
    var onEditModeChange: (() -> Void)?

    private unowned let document: MarkerDocument
    private var scrollView: NSScrollView!
    private var textView: MarkdownTextView!

    private let zoom = ZoomController()

    private var theme: MarkerTheme {
        MarkerApp.appearance.theme(for: viewIfLoaded, zoom: zoom.scale)
    }

    init(document: MarkerDocument) {
        self.document = document
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("unavailable") }

    deinit { NotificationCenter.default.removeObserver(self) }

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
        applyAppearance()
        // The harness needs to be able to open straight into edit mode, since the
        // EDT and TB rows are about what the window looks like in that state.
        if ProcessInfo.processInfo.environment["MARKER_EDIT"] != nil,
           MarkerApp.license.state.allowsEditing {
            editMode = .editing
        }
        applyEditMode()

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
        textView.onEffectiveAppearanceChange = { [weak self] in self?.appearanceDidChange() }
    }

    @objc private func appearanceDidChange() {
        let theme = self.theme
        // The scroll view has to stop painting too, or an opaque band sits between
        // the material and the text.
        scrollView.drawsBackground = !theme.isTranslucent
        scrollView.backgroundColor = theme.isTranslucent ? .clear : theme.colors.background
        if let contentView = view.window?.contentView {
            WindowMaterial.apply(theme, to: contentView)
        }
        render()
    }

    /// Called once the view is in a window, when the material can be installed.
    func applyAppearance() {
        appearanceDidChange()
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
        let renderer = DocumentRenderer(theme: theme, mode: .interactive)
        let content: NSAttributedString
        if editMode == .editing {
            // The source editor shows markdown the user is about to type into, so it
            // is left uncoloured. Colouring it as code would misdescribe it.
            content = renderer.renderPlain(document.source.text)
        } else {
            switch document.presentation {
            case .markdown: content = renderer.render(document.source)
            case .json: content = renderer.renderPlain(document.source.text, language: "json")
            case .yaml: content = renderer.renderPlain(document.source.text, language: "yaml")
            case .plainText: content = renderer.renderPlain(document.source.text)
            }
        }
        textView.setContent(content, theme: theme, availableWidth: width)
    }

    // MARK: Edit mode

    func toggleEditMode() {
        // Leaving edit mode is always allowed. Entering it is what Pro gates, so a
        // trial that expires while a document is open never traps someone inside an
        // editor they can no longer use.
        if editMode == .reading, !MarkerApp.license.state.allowsEditing {
            presentTrialEnded()
            return
        }
        editMode = editMode == .reading ? .editing : .reading
        applyEditMode()
        onEditModeChange?()
    }

    private func presentTrialEnded() {
        let alert = NSAlert()
        alert.messageText = "Your trial has ended"
        alert.informativeText = """
        Marker is a viewer without Pro. Reading, Mermaid, LaTeX, code and Quick Look         previews stay free forever. Enter a licence key in Settings to edit again.
        """
        alert.addButton(withTitle: "Open Settings")
        alert.addButton(withTitle: "Not Now")
        alert.alertStyle = .informational
        if alert.runModal() == .alertFirstButtonReturn {
            SettingsWindowController.shared.showWindow(nil)
        }
    }

    private func applyEditMode() {
        let editing = editMode == .editing
        textView.isEditable = editing
        // AppKit's undo stack is correct here and only here. In source mode the
        // storage is the source, so its ranges stay valid. The ban on it applies to
        // the rendered path, where a re-render replaces block text underneath ranges
        // the undo stack is still holding.
        textView.allowsUndo = editing
        textView.delegate = editing ? self : nil
        render()
        if editing { view.window?.makeFirstResponder(textView) }
    }

    // MARK: Find

    func showFindBar() {
        textView.performTextFinderAction(
            NSMenuItem(title: "", action: nil, keyEquivalent: "").withFinderTag(.showFindInterface)
        )
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


// MARK: - Source editing

extension DocumentViewController: NSTextViewDelegate {

    /// In source mode the storage holds the raw markdown, so keeping the document in
    /// step is a straight copy. `NSDocument` then owns the dirty dot, the close
    /// sheet and ⌘S with no further code.
    func textDidChange(_ notification: Notification) {
        guard editMode == .editing else { return }
        document.replaceSource(with: textView.string)
    }
}

private extension NSMenuItem {
    /// `performTextFinderAction` reads the action off the sender's tag, so a
    /// programmatic call needs a sender carrying one.
    func withFinderTag(_ action: NSTextFinder.Action) -> NSMenuItem {
        tag = action.rawValue
        return self
    }
}
