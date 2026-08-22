import AppKit

/// The document surface.
///
/// TextKit 2 only. Never touch `.layoutManager` on this view: reading that
/// property is a permanent TextKit 1 fallback trigger and silently disables both
/// `NSTextAttachmentViewProvider` and viewport layout, which the table and
/// diagram attachments depend on. `.textStorage` is safe, because
/// `NSTextContentStorage` is an `NSTextStorageObserving` client of it.
public final class MarkdownTextView: NSTextView {

    public convenience init(theme: MarkerTheme) {
        let container = NSTextContainer(size: CGSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        let layoutManager = NSTextLayoutManager()
        layoutManager.textContainer = container
        let contentStorage = NSTextContentStorage()
        contentStorage.addTextLayoutManager(layoutManager)

        self.init(frame: .zero, textContainer: container)
        configure(theme: theme)
    }

    private func configure(theme: MarkerTheme) {
        currentTheme = theme
        isRichText = true
        isSelectable = true
        isEditable = false
        // Undo is owned by UndoCoordinator, not AppKit. NSTextView's stack holds
        // storage-space ranges that go stale the moment a re-render replaces a
        // block's text, which is a guaranteed corruption source.
        allowsUndo = false
        isAutomaticQuoteSubstitutionEnabled = false
        isAutomaticDashSubstitutionEnabled = false
        isAutomaticTextReplacementEnabled = false
        // We own the frame, not AppKit. With isVerticallyResizable on, NSTextView
        // recomputes its own height from TextKit 2's viewport layout on every layout
        // pass, which under TK2 means "however much is currently on screen". Two
        // owners of one frame produced a height that oscillated between 662 and
        // 167925 points depending on when it was read, and a scroll view that
        // stopped partway down whichever value it happened to see.
        isVerticallyResizable = false
        isHorizontallyResizable = false
        autoresizingMask = [.width]
        drawsBackground = true
        backgroundColor = theme.colors.background
        textContainerInset = CGSize(width: theme.metrics.pageInset, height: theme.metrics.pageInset)

        // Find: ⌘F is these two lines. NSTextView owns an NSTextFinder internally
        // when usesFindBar is set, and that finder's default
        // incrementalSearchingShouldDimContentView == true dims everything except
        // the matches, so every match reads as highlighted for free.
        //
        // The alternative is our own NSTextFinder with that flag off, drawing
        // highlight boxes from its KVO-observable incrementalMatchRanges. That is
        // the upgrade if the dim-and-reveal look fails the FIND rows in the QA
        // pass; it is not worth the code before then.
        usesFindBar = true
        isIncrementalSearchingEnabled = true
    }

    private var currentTheme: MarkerTheme?

    // MARK: Decoration

    /// Paints code panels, quote bars and rules behind the glyphs.
    ///
    /// Done here rather than with `.backgroundColor` attributes because those paint
    /// per glyph run, which gives a ragged right edge that stops at the last
    /// character instead of a panel that spans the column. Fragments belonging to
    /// one block are unioned first, so a ten line code block gets one rounded
    /// rectangle rather than ten.
    public override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)
        guard let theme = currentTheme, let layoutManager = textLayoutManager else { return }

        let origin = textContainerOrigin
        var panels: [(decoration: MarkerDecoration, block: Int, frame: NSRect)] = []

        layoutManager.enumerateTextLayoutFragments(
            from: layoutManager.documentRange.location,
            options: [.ensuresLayout]
        ) { fragment in
            // Read attributes off the paragraph element itself rather than converting
            // its NSTextRange back into an NSRange, which needs offset arithmetic that
            // is easy to get wrong and buys nothing here.
            guard let paragraph = fragment.textElement as? NSTextParagraph,
                  paragraph.attributedString.length > 0,
                  let decoration = paragraph.attributedString.attribute(
                      .markerDecoration, at: 0, effectiveRange: nil) as? MarkerDecoration
            else { return true }
            let block = paragraph.attributedString.attribute(
                .markerBlock, at: 0, effectiveRange: nil) as? Int ?? -1

            var frame = fragment.layoutFragmentFrame
            frame.origin.x += origin.x
            frame.origin.y += origin.y

            if let last = panels.last, last.decoration == decoration, last.block == block {
                panels[panels.count - 1].frame = last.frame.union(frame)
            } else {
                panels.append((decoration, block, frame))
            }
            return frame.minY < rect.maxY
        }

        let contentWidth = (textContainer?.size.width ?? bounds.width)
        for panel in panels {
            draw(panel.decoration, in: panel.frame, contentWidth: contentWidth, theme: theme)
        }
    }

    private func draw(
        _ decoration: MarkerDecoration, in frame: NSRect, contentWidth: CGFloat, theme: MarkerTheme
    ) {
        let inset = theme.bodyPointSize * 0.5
        switch decoration {
        case .codeBlock:
            let panel = NSRect(
                x: textContainerOrigin.x, y: frame.minY - inset * 0.6,
                width: contentWidth, height: frame.height + inset * 1.2
            )
            let path = NSBezierPath(roundedRect: panel,
                                    xRadius: theme.metrics.codeCornerRadius,
                                    yRadius: theme.metrics.codeCornerRadius)
            theme.colors.codeBackground.setFill()
            path.fill()
            theme.colors.codeBorder.setStroke()
            path.lineWidth = 1
            path.stroke()

        case .placeholder:
            let panel = NSRect(
                x: textContainerOrigin.x, y: frame.minY - inset * 0.6,
                width: contentWidth, height: frame.height + inset * 1.2
            )
            let path = NSBezierPath(roundedRect: panel,
                                    xRadius: theme.metrics.codeCornerRadius,
                                    yRadius: theme.metrics.codeCornerRadius)
            path.setLineDash([5, 4], count: 2, phase: 0)
            theme.colors.codeBorder.setStroke()
            path.lineWidth = 1
            path.stroke()

        case .quote(let depth):
            let unit = theme.bodyPointSize * 1.6
            for level in 0 ..< depth {
                let x = textContainerOrigin.x + CGFloat(level) * unit + unit * 0.25
                let bar = NSRect(x: x, y: frame.minY, width: 3, height: frame.height)
                theme.colors.quoteBar.setFill()
                NSBezierPath(roundedRect: bar, xRadius: 1.5, yRadius: 1.5).fill()
            }

        case .thematicBreak:
            let y = frame.midY
            let line = NSRect(x: textContainerOrigin.x, y: y, width: contentWidth, height: 1)
            theme.colors.rule.setFill()
            line.fill()
        }
    }

    /// Set while `setContent` is replacing the whole document, so the sizing and
    /// scrolling hooks below do not fire once per intermediate state.
    private var isSettingContent = false

    /// Typing has to grow the frame, and the caret has to stay in view.
    ///
    /// Both of these come free with `isVerticallyResizable`, and both were lost when
    /// this view took ownership of its own frame to stop AppKit and TextKit 2
    /// fighting over it. Owning the frame means owning everything that used to
    /// follow from it: without the first, the document stops growing as you type and
    /// the new lines are unreachable; without the second, pressing Down moves the
    /// caret somewhere you cannot see.
    public override func didChangeText() {
        super.didChangeText()
        guard !isSettingContent, let theme = currentTheme else { return }
        sizeToFitContent(theme: theme, availableWidth: frame.width)
        scrollToCaret()
    }

    public override func setSelectedRanges(
        _ ranges: [NSValue],
        affinity: NSSelectionAffinity,
        stillSelecting: Bool
    ) {
        super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: stillSelecting)
        // Not while dragging a selection: the view should follow the pointer, and
        // scrolling underneath it fights the drag.
        guard !isSettingContent, !stillSelecting else { return }
        scrollToCaret()
    }

    /// Scrolls the insertion point into view, with a little room around it so the
    /// caret never sits flush against the top or bottom edge.
    private func scrollToCaret() {
        guard let scrollView = enclosingScrollView else { return }
        let caret = selectedRange()
        guard caret.location <= (string as NSString).length else { return }

        var rect = firstRect(forCharacterRange: caret, actualRange: nil)
        guard rect.height > 0 else { return }
        rect = convert(rect, from: nil)

        let margin = (currentTheme?.bodyPointSize ?? 14) * 2
        let visible = scrollView.documentVisibleRect
        if rect.minY - margin < visible.minY {
            scroll(NSPoint(x: 0, y: max(rect.minY - margin, 0)))
        } else if rect.maxY + margin > visible.maxY {
            scroll(NSPoint(x: 0, y: rect.maxY + margin - visible.height))
        }
    }

    /// True while an input method is composing. The source mirror records the
    /// range but performs no source edit until composition ends, because
    /// mirroring provisional text kills the input session.
    public var isComposing: Bool { hasMarkedText() }

    /// The one way content gets into this view.
    ///
    /// Every host goes through here: the document window, the Quick Look extension
    /// and the offscreen renderer. That is deliberate. The three steps below have to
    /// happen together and in this order, and when two of the three hosts skipped
    /// the last one, both of them scrolled short of the end of the document.
    public func setContent(_ attributed: NSAttributedString, theme: MarkerTheme, availableWidth: CGFloat) {
        isSettingContent = true
        defer { isSettingContent = false }

        currentTheme = theme
        applyBackground(theme)
        applyMeasure(theme: theme, availableWidth: availableWidth)
        textStorage?.setAttributedString(attributed)
        sizeToFitContent(theme: theme, availableWidth: availableWidth)
        needsDisplay = true
    }

    /// Lays the whole document out and sizes the frame to match.
    ///
    /// `ensureLayout(for: documentRange)` is not enough on its own. Once the text
    /// view is inside a scroll view it has an `NSTextViewportLayoutController`, and
    /// layout stays bounded to the viewport, so `usageBoundsForTextContainer` comes
    /// back describing roughly one screenful. On a 5450 line fixture that was 1731
    /// points instead of 167925, which is precisely why scrolling stopped early:
    /// the scroll view was told the document was one screen long.
    ///
    /// Walking every fragment with `.ensuresLayout` is the documented way to force
    /// the whole document through layout, and the maximum fragment bottom is then
    /// the real content height.
    ///
    /// This trades TextKit 2's laziness for correctness. It is the right trade at
    /// this size, and it runs on open, on zoom commit and on theme switch, so if a
    /// large document ever feels slow the answer is viewport-driven sizing, not
    /// removing this call.
    @discardableResult
    public func sizeToFitContent(theme: MarkerTheme, availableWidth: CGFloat) -> CGFloat {
        guard let layoutManager = textLayoutManager else { return frame.height }

        var contentBottom: CGFloat = 0
        layoutManager.enumerateTextLayoutFragments(
            from: layoutManager.documentRange.location,
            options: [.ensuresLayout]
        ) { fragment in
            contentBottom = max(contentBottom, fragment.layoutFragmentFrame.maxY)
            return true
        }

        let contentHeight = contentBottom + theme.metrics.pageInset * 2
        // Never shorter than the clip view, or the background stops partway down a
        // window that is taller than its document.
        let minimumHeight = enclosingScrollView?.contentSize.height ?? 0
        let height = max(contentHeight, minimumHeight)
        if abs(height - frame.height) > 0.5 || abs(availableWidth - frame.width) > 0.5 {
            setFrameSize(NSSize(width: availableWidth, height: height))
        }
        return height
    }

    /// Re-theme without rebuilding the view, so a light-to-dark switch keeps the
    /// scroll position and the selection.
    public func apply(theme: MarkerTheme, availableWidth: CGFloat? = nil) {
        currentTheme = theme
        applyBackground(theme)
        let width = availableWidth ?? bounds.width
        applyMeasure(theme: theme, availableWidth: width)
        sizeToFitContent(theme: theme, availableWidth: width)
        needsDisplay = true
    }

    /// Translucency is a clear background colour, never `drawsBackground = false`.
    ///
    /// Code panels, quote bars and thematic rules are painted in
    /// `drawBackground(in:)`, and NSTextView only calls that when it is drawing a
    /// background. Turning it off would silently strip every decoration from the
    /// page in glass mode, which looks like a rendering bug rather than a
    /// configuration one.
    private func applyBackground(_ theme: MarkerTheme) {
        drawsBackground = true
        backgroundColor = theme.isTranslucent ? .clear : theme.colors.background
    }

    /// The system flipping between light and dark has to re-render, because the
    /// palette is concrete colour values chosen when the theme was built. Without
    /// this, "Liquid Glass follows the system" would only be true at launch.
    public var onEffectiveAppearanceChange: (() -> Void)?

    public override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        onEffectiveAppearanceChange?()
    }

    /// The width the measure was last computed against, so a resize can tell a real
    /// width change from the many layout passes that do not change it.
    public private(set) var measuredWidth: CGFloat = 0

    /// Caps the column at the theme's readable measure and centres it.
    ///
    /// Without this the text runs the full width of the window, which is unreadable
    /// on a wide display and is the single biggest difference between a markdown
    /// viewer that looks designed and one that looks like a text dump.
    public func applyMeasure(theme: MarkerTheme, availableWidth: CGFloat) {
        let measure = min(theme.metrics.contentWidth * theme.zoom,
                          max(availableWidth - theme.metrics.pageInset * 2, 200))
        let horizontal = max((availableWidth - measure) / 2, theme.metrics.pageInset)
        textContainerInset = CGSize(width: horizontal, height: theme.metrics.pageInset)
        textContainer?.size = CGSize(width: measure, height: .greatestFiniteMagnitude)
        // The container width is now ours, not the view's, so a resize has to
        // re-run this rather than relying on the view to track it.
        textContainer?.widthTracksTextView = false
        measuredWidth = availableWidth
    }
}
