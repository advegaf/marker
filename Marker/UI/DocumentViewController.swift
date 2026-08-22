import AppKit
import MarkerCore
import MarkerRender

/// Hosts the document surface: a scroll view over one TextKit 2 text view.
final class DocumentViewController: NSViewController {

    /// Reading is the default and nothing enters editing on its own. The product is
    /// a viewer first, so the caret has to be asked for.
    ///
    /// `editing` is the rendered page with a caret in it, which is what the product
    /// promises. `source` shows the raw markdown, which is what you want when a
    /// construct cannot be edited on the page, or when you would simply rather see
    /// the marks.
    enum EditMode { case reading, editing, source }

    private(set) var editMode: EditMode = .reading

    /// Lets the window controller keep the toolbar's Edit button in step without the
    /// view controller knowing the toolbar exists.
    var onEditModeChange: (() -> Void)?

    private unowned let document: MarkerDocument
    private var container: NSView!
    private var banner: ReloadBanner!
    private var scrollView: NSScrollView!
    private var textView: MarkdownTextView!

    private let zoom = ZoomController()
    private let slashMenu = SlashCommandMenu()
    private var mirror: WYSIWYGMirror!
    /// The map describing what is currently on screen, kept so slash commands and
    /// the caret guard can ask where a render offset came from.
    private var renderIndex: BlockIndex = .empty

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

        container = NSView(frame: NSRect(x: 0, y: 0, width: 900, height: 700))
        scrollView.frame = container.bounds
        scrollView.autoresizingMask = [.width, .height]
        container.addSubview(scrollView)

        banner = ReloadBanner(frame: NSRect(x: 0, y: 0, width: 900, height: ReloadBanner.height))
        banner.autoresizingMask = [.width]
        banner.isHidden = true
        container.addSubview(banner)

        view = container
        // The watcher delivers on the main queue, so bridging back to the main actor
        // here is a statement of that fact rather than a hop.
        mirror = WYSIWYGMirror(textView: textView)
        mirror.currentSource = { [weak self] in self?.document.source ?? MarkdownSource("") }
        mirror.applyEdit = { [weak self] edit in
            guard let self else { return }
            var source = self.document.source
            source.apply(edit)
            self.document.replaceSource(with: source.text)
        }
        mirror.render = { [weak self] source in
            guard let self else { return (NSAttributedString(), .empty) }
            let rendered = DocumentRenderer(theme: self.theme, mode: .interactive)
                .renderDocument(source)
            self.renderIndex = rendered.index
            return (rendered.attributed, rendered.index)
        }
        mirror.onRefusal = { [weak self] refusal in self?.explain(refusal) }

        slashMenu.onPick = { [weak self] command in self?.insert(command) }
        document.onExternalChange = { [weak self] change in
            MainActor.assumeIsolated { self?.fileChanged(change) }
        }
        applyAppearance()
        // The harness needs to be able to open straight into edit mode, since the
        // EDT and TB rows are about what the window looks like in that state.
        // Two flags, because the QA rows for the two editors are different.
        if ProcessInfo.processInfo.environment["MARKER_SOURCE"] != nil {
            editMode = .source
        } else if ProcessInfo.processInfo.environment["MARKER_EDIT"] != nil {
            editMode = .editing
        }
        applyEditMode()
        typeFromLaunchEnvironmentIfNeeded()

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

    // MARK: External change

    private func layoutBanner() {
        guard let container, let banner, let scrollView else { return }
        let height = banner.isHidden ? 0 : ReloadBanner.height
        banner.frame = NSRect(
            x: 0, y: container.bounds.height - ReloadBanner.height,
            width: container.bounds.width, height: ReloadBanner.height
        )
        scrollView.frame = NSRect(
            x: 0, y: 0, width: container.bounds.width, height: container.bounds.height - height
        )
    }

    private func fileChanged(_ change: FileWatcher.Change) {
        let theme = self.theme

        switch change {
        case .vanished:
            banner.show(
                message: "\(document.displayName ?? "This file") was moved or deleted.",
                primaryTitle: "Save Again",
                secondaryTitle: "Ignore",
                theme: theme,
                onPrimary: { [weak self] in self?.document.save(nil) },
                onSecondary: { [weak self] in self?.layoutBanner() }
            )

        case .modified:
            // A document with no unsaved edits has nothing to lose, so reloading
            // silently is what someone regenerating a file from a build expects.
            // Asking every time would make the app unusable next to a generator.
            guard document.isDocumentEdited else {
                reloadPreservingPosition()
                return
            }
            banner.show(
                message: "This file changed on disk. You have unsaved changes.",
                primaryTitle: "Reload",
                secondaryTitle: "Keep Mine",
                theme: theme,
                onPrimary: { [weak self] in self?.reloadPreservingPosition() },
                onSecondary: { [weak self] in self?.layoutBanner() }
            )
        }
        layoutBanner()
    }

    /// Reloads and keeps the reader where they were.
    ///
    /// Anchored on the fraction of the document scrolled past rather than on a pixel
    /// offset, because the file just changed length and a pixel offset would land
    /// somewhere arbitrary.
    private func reloadPreservingPosition() {
        let previousHeight = max(textView.frame.height, 1)
        let previousOffset = scrollView.contentView.bounds.origin.y
        let fraction = previousOffset / previousHeight

        do {
            try document.reloadFromDisk()
        } catch {
            banner.show(
                message: "Could not re-read this file.",
                primaryTitle: "Try Again",
                secondaryTitle: "Ignore",
                theme: theme,
                onPrimary: { [weak self] in self?.reloadPreservingPosition() },
                onSecondary: { [weak self] in self?.layoutBanner() }
            )
            layoutBanner()
            return
        }

        render()
        let restored = fraction * textView.frame.height
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: restored))
        scrollView.reflectScrolledClipView(scrollView.contentView)
        layoutBanner()
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
        return "bytes=\(document.source.byteCount) attrLen=\(textView.textStorage?.length ?? -1) fragments=\(fragments) bottom=\(Int(bottom)) slashMenu=\(slashMenu.isVisible) slashMatches=\(slashMenu.visibleCount)"
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
        if editMode == .source {
            // The source editor shows markdown the user is about to type into, so it
            // is left uncoloured. Colouring it as code would misdescribe it.
            content = renderer.renderPlain(document.source.text)
        } else {
            switch document.presentation {
            case .markdown:
                let rendered = renderer.renderDocument(document.source)
                renderIndex = rendered.index
                mirror?.adopt(index: rendered.index)
                content = rendered.attributed
            case .json: content = renderer.renderPlain(document.source.text, language: "json")
            case .yaml: content = renderer.renderPlain(document.source.text, language: "yaml")
            case .plainText: content = renderer.renderPlain(document.source.text)
            }
        }
        // Every write to the storage that did not come from a keystroke has to be
        // marked as derived, or the mirror maps it back into the source.
        if let mirror {
            mirror.performingDerivedUpdate {
                textView.setContent(content, theme: theme, availableWidth: width)
            }
        } else {
            textView.setContent(content, theme: theme, availableWidth: width)
        }
    }

    // MARK: Edit mode

    func toggleEditMode() {
        editMode = editMode == .reading ? .editing : .reading
        applyEditMode()
        onEditModeChange?()
    }

    private func applyEditMode() {
        let editable = editMode != .reading
        if !editable { slashMenu.hide() }
        textView.isEditable = editable
        // AppKit's undo stack is correct in source mode and only there: the storage
        // is the source, so its ranges stay valid. In the rendered path a re-render
        // replaces block text underneath ranges the undo stack is still holding,
        // which is a guaranteed corruption source.
        textView.allowsUndo = editMode == .source
        textView.delegate = editable ? self : nil
        // The mirror only watches the rendered path. In source mode the storage is
        // the source already and there is nothing to map.
        textView.textStorage?.delegate = editMode == .editing ? mirror : nil
        render()
        if editable { view.window?.makeFirstResponder(textView) }
    }

    /// Says why a keystroke did not land, once, quietly.
    ///
    /// Silently swallowing it is what makes an editor feel broken, and an alert for
    /// every refused character would be worse. The window title bar carries it.
    private func explain(_ refusal: EditMapper.Refusal) {
        let message: String
        switch refusal {
        case .syntheticText: message = "That part is drawn from the markdown and cannot be typed over."
        case .attachment: message = "Edit this through its own controls, or switch to the markdown source."
        case .crossesBlocks: message = "That edit spans two blocks. Switch to the markdown source for it."
        case .opaqueBlock: message = "This block could not be mapped. Switch to the markdown source to edit it."
        }
        view.window?.subtitle = message
        // Cleared on the next successful edit or after a moment, so it does not
        // become a permanent accusation.
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
            if self?.view.window?.subtitle == message { self?.view.window?.subtitle = "" }
        }
    }

    /// Toggles the raw markdown view, for anything the page cannot edit in place.
    @objc func toggleSourceMode(_ sender: Any?) {
        editMode = editMode == .source ? .reading : .source
        applyEditMode()
        onEditModeChange?()
    }

    /// `MARKER_TYPE=/tab` types into the editor at launch, so a QA run can reach the
    /// command menu without driving the keyboard. It goes through the same path a
    /// keystroke does rather than setting the string directly, or it would prove
    /// nothing about the trigger.
    private func typeFromLaunchEnvironmentIfNeeded() {
        guard editMode != .reading,
              let text = ProcessInfo.processInfo.environment["MARKER_TYPE"],
              isHarnessTarget else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            // `MARKER_CARET` places the caret by rendered offset first, so a QA run
            // can type into a specific construct rather than only at the end.
            let length = (self.textView.string as NSString).length
            let requested = ProcessInfo.processInfo.environment["MARKER_CARET"].flatMap(Int.init)
            let selectLength = ProcessInfo.processInfo.environment["MARKER_SELECT"].flatMap(Int.init) ?? 0
            let end = NSRange(
                location: min(requested ?? length, length),
                length: min(selectLength, max(length - min(requested ?? length, length), 0))
            )
            self.textView.setSelectedRange(end)
            // An empty MARKER_TYPE means "select only". Inserting an empty string
            // over a selection deletes it, which is not what a format probe wants.
            if !text.isEmpty {
                self.textView.insertText(text, replacementRange: end)
            }
            // The source is the thing under test in the rendered path: the display
            // could look right while the file behind it is wrong.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                FileHandle.standardError.write(Data(
                    "[source]\n\(self.document.source.text)\n[/source]\n".utf8
                ))
            }

            // `MARKER_PICK=1` then chooses the highlighted command, through the same
            // selector Return goes through, so the harness exercises the real path.
            if let format = ProcessInfo.processInfo.environment["MARKER_FORMAT"] {
                let styles: [String: InlineFormat.Style] = [
                    "bold": .strong, "italic": .emphasis,
                    "strike": .strikethrough, "code": .code,
                ]
                if let style = styles[format] {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        self.toggleFormat(style)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                            FileHandle.standardError.write(Data(
                                "[source]\n\(self.document.source.text)\n[/source]\n".utf8
                            ))
                        }
                    }
                }
                return
            }
            guard ProcessInfo.processInfo.environment["MARKER_PICK"] != nil else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                _ = self.slashMenu.handle(#selector(NSResponder.insertNewline(_:)))
                // Reported after a turn of the run loop: closing the popover can
                // defer the pick, and printing immediately raced it.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    FileHandle.standardError.write(Data(
                        "[picked]\n\(self.textView.string)\n[/picked]\n".utf8
                    ))
                }
            }
        }
    }

    /// Whether this document is the one the harness asked for.
    ///
    /// macOS restores windows from previous sessions, so without this every restored
    /// document also acts on the launch flags. That produced four insertions in four
    /// documents and a report about the wrong one, which looked like the feature
    /// failing when it had actually worked.
    private var isHarnessTarget: Bool {
        guard let requested = ProcessInfo.processInfo.environment["MARKER_OPEN"] else { return true }
        let wanted = URL(fileURLWithPath: (requested as NSString).expandingTildeInPath)
            .resolvingSymlinksInPath().standardizedFileURL
        return document.fileURL?.resolvingSymlinksInPath().standardizedFileURL == wanted
    }

    // MARK: Slash commands

    /// Shows, filters or hides the command menu based on where the caret is.
    ///
    /// Driven from the caret rather than from the keystroke, so it behaves the same
    /// whether the slash was typed, pasted, or arrived by moving the caret back into
    /// a token that was already there.
    private func updateSlashMenu() {
        guard editMode != .reading else { return slashMenu.hide() }

        let caret = textView.selectedRange().location
        let source = editMode == .source ? MarkdownSource(textView.string) : document.source
        guard caret <= source.byteCount,
              let token = SlashCommandInsertion.activeToken(at: renderToSourceOffset(caret), in: source)
        else { return slashMenu.hide() }

        let matches = SlashCommand.matching(SlashCommandInsertion.query(for: token, in: source))
        guard !matches.isEmpty else { return slashMenu.hide() }

        if slashMenu.isVisible {
            slashMenu.update(commands: matches)
        } else {
            slashMenu.show(commands: matches, at: caretRect(), in: textView)
        }
        if ProcessInfo.processInfo.environment["MARKER_DEBUG_SLASH"] != nil {
            FileHandle.standardError.write(Data(
                "[slash] token=\(token) matches=\(matches.count) visible=\(slashMenu.isVisible)\n".utf8
            ))
        }
    }

    /// In source mode the storage is the source, so the two offsets differ only by
    /// UTF-16 against UTF-8. Converting through the string keeps multibyte text
    /// honest.
    private func renderToSourceOffset(_ location: Int) -> Int {
        // Source mode: the storage is the source, so the two differ only by UTF-16
        // against UTF-8.
        if editMode == .source {
            let text = textView.string as NSString
            guard location <= text.length else { return 0 }
            return text.substring(to: location).utf8.count
        }
        // Rendered mode: the storage is derived, so the block map is the only thing
        // that knows where a render offset came from.
        return renderIndex.sourceOffset(forRender: location) ?? 0
    }

    private func sourceToRenderOffset(_ byteOffset: Int) -> Int {
        if editMode == .source {
            let bytes = Array(textView.string.utf8)
            let clamped = max(0, min(byteOffset, bytes.count))
            let prefix = String(bytes: bytes[0 ..< clamped], encoding: .utf8) ?? ""
            return (prefix as NSString).length
        }
        return renderIndex.renderOffset(forSource: byteOffset) ?? 0
    }

    private func caretRect() -> NSRect {
        let range = textView.selectedRange()
        guard let layoutManager = textView.textLayoutManager,
              let contentManager = layoutManager.textContentManager,
              let start = contentManager.location(
                  contentManager.documentRange.location, offsetBy: range.location
              ),
              let fragment = layoutManager.textLayoutFragment(for: start)
        else { return NSRect(x: 0, y: 0, width: 1, height: 1) }

        var frame = fragment.layoutFragmentFrame
        frame.origin.x += textView.textContainerOrigin.x
        frame.origin.y += textView.textContainerOrigin.y
        // A one-line-tall sliver, so the popover sits under the caret's line rather
        // than under the whole paragraph.
        return NSRect(x: frame.minX, y: frame.minY, width: frame.width, height: frame.height)
    }

    private func insert(_ command: SlashCommand) {
        let source = editMode == .source ? MarkdownSource(textView.string) : document.source
        let caret = renderToSourceOffset(textView.selectedRange().location)
        let debug = ProcessInfo.processInfo.environment["MARKER_DEBUG_SLASH"] != nil
        guard let token = SlashCommandInsertion.activeToken(at: caret, in: source) else {
            if debug { FileHandle.standardError.write(Data("[insert] no token at \(caret)\n".utf8)) }
            return
        }

        let result = SlashCommandInsertion.apply(command, replacing: token, in: source)

        // In the rendered path the edit goes to the source and the page is rebuilt
        // from it, rather than being typed into the storage.
        if editMode == .editing {
            var updated = source
            updated.apply(result.edit)
            document.replaceSource(with: updated.text)
            render()
            if let offset = renderIndex.renderOffset(forSource: result.caret) {
                textView.setSelectedRange(NSRange(location: offset, length: 0))
            }
            return
        }

        let replaceRange = NSRange(
            location: sourceToRenderOffset(token.lowerBound),
            length: sourceToRenderOffset(token.upperBound) - sourceToRenderOffset(token.lowerBound)
        )
        // Through shouldChangeText so the undo stack records it as one action: a
        // slash command should undo in a single press, not character by character.
        guard textView.shouldChangeText(in: replaceRange, replacementString: result.edit.replacement) else {
            if debug { FileHandle.standardError.write(Data("[insert] refused \(replaceRange)\n".utf8)) }
            return
        }
        if debug { FileHandle.standardError.write(Data("[insert] \(command.name) into \(replaceRange)\n".utf8)) }
        textView.textStorage?.replaceCharacters(in: replaceRange, with: result.edit.replacement)
        textView.didChangeText()
        textView.setSelectedRange(NSRange(location: sourceToRenderOffset(result.caret), length: 0))
    }

    // MARK: Inline formatting

    @objc func toggleBold(_ sender: Any?) { toggleFormat(.strong) }
    @objc func toggleItalic(_ sender: Any?) { toggleFormat(.emphasis) }
    @objc func toggleStrikethrough(_ sender: Any?) { toggleFormat(.strikethrough) }
    @objc func toggleInlineCode(_ sender: Any?) { toggleFormat(.code) }

    /// Applies a style to the selection, in either editing mode.
    ///
    /// The selection is a render range, so it is mapped to source bytes first. The
    /// edit then goes to the source and the page is rebuilt from it, which is the
    /// same path every other edit takes.
    private func toggleFormat(_ style: InlineFormat.Style) {
        guard editMode != .reading else { return }
        let selection = textView.selectedRange()
        guard selection.length > 0 else {
            view.window?.subtitle = "Select some text first."
            return
        }

        let source = editMode == .source ? MarkdownSource(textView.string) : document.source
        let lower = renderToSourceOffset(selection.location)
        let upper = renderToSourceOffset(selection.location + selection.length)
        guard lower < upper else { return }

        if ProcessInfo.processInfo.environment["MARKER_DEBUG_FORMAT"] != nil {
            FileHandle.standardError.write(Data(
                "[fmt] sel=\(selection) source=\(lower)..<\(upper) text=<<<\(source.slice(lower ..< upper) ?? "nil")>>>\n".utf8
            ))
        }
        let blocks = MarkdownParser.parse(source).blocks
        switch InlineFormat.toggle(style, over: lower ..< upper, in: source, blocks: blocks) {
        case .success(let result):
            var updated = source
            for edit in result.edits { updated.apply(edit) }
            document.replaceSource(with: updated.text)
            render()
            restoreSelection(result.selection)

        case .failure(let refusal):
            switch refusal {
            case .emptySelection: view.window?.subtitle = "Select some text first."
            case .crossesBlocks: view.window?.subtitle = "That selection spans two blocks."
            case .notFormattable: view.window?.subtitle = "This block cannot carry inline styling."
            }
        }
    }

    private func restoreSelection(_ sourceRange: Range<Int>) {
        let start = sourceToRenderOffset(sourceRange.lowerBound)
        let end = sourceToRenderOffset(sourceRange.upperBound)
        let length = (textView.string as NSString).length
        guard start <= length, end <= length, start <= end else { return }
        textView.setSelectedRange(NSRange(location: start, length: end - start))
    }

    /// Ticks the menu item when the selection already carries the style.
    func isFormatActive(_ style: InlineFormat.Style) -> Bool {
        let selection = textView.selectedRange()
        guard selection.length > 0, editMode != .reading else { return false }
        let source = editMode == .source ? MarkdownSource(textView.string) : document.source
        let lower = renderToSourceOffset(selection.location)
        let upper = renderToSourceOffset(selection.location + selection.length)
        guard lower < upper else { return false }
        return InlineFormat.isActive(style, over: lower ..< upper, blocks: MarkdownParser.parse(source).blocks)
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
        layoutBanner()
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
    ///
    /// **Only** in source mode. In the rendered path the storage holds derived text
    /// with the markup stripped out of it, and copying that into the source replaces
    /// the document with its own rendering: headings lose their hashes, bold loses
    /// its asterisks, and the file is destroyed on the next save. The mirror owns
    /// that path, and it maps edits back rather than copying them.
    func textDidChange(_ notification: Notification) {
        guard editMode == .source else {
            updateSlashMenu()
            return
        }
        document.replaceSource(with: textView.string)
        updateSlashMenu()
    }

    func textViewDidChangeSelection(_ notification: Notification) {
        // Moving the caret out of a token closes the menu, and moving it back in
        // reopens it, which is what makes the trigger feel like part of the editor
        // rather than a keystroke handler.
        updateSlashMenu()
    }

    /// Arrow keys, Return and Escape belong to the menu while it is open.
    func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        slashMenu.handle(selector)
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
