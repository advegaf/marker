import AppKit
import MarkerCore
import MarkerRender

/// Keeps the source in step with edits made to the rendered page.
///
/// The loop is: AppKit mutates the storage, this maps that change back to a source
/// edit, applies it, reparses, and replaces the storage with the new render. The
/// raw markdown stays the source of truth throughout; the attributed string is
/// always derived output.
///
/// It is deliberately a `didProcessEditing` observer rather than a
/// `shouldChangeTextIn` veto. Vetoing every change and re-applying it by hand is
/// the tempting shape and it breaks input methods outright, along with autocorrect,
/// dictation and Services.
@MainActor
final class WYSIWYGMirror: NSObject, NSTextStorageDelegate {

    /// Set while this class is the one writing to the storage, so its own writes do
    /// not come back around as user edits.
    private var isApplyingDerivedUpdate = false

    private unowned let textView: MarkdownTextView

    /// The index describing the storage as it is *now*, before the next edit. An
    /// edit is reported in the coordinates of the text before it happened, so the
    /// map has to be the one from before too.
    private var index: BlockIndex = .empty

    /// Source, render and caret, supplied by the owner.
    var currentSource: () -> MarkdownSource = { MarkdownSource("") }
    var applyEdit: (TextEdit) -> Void = { _ in }
    var render: (MarkdownSource) -> (attributed: NSAttributedString, index: BlockIndex) = {
        (NSAttributedString(string: $0.text), .empty)
    }
    /// Raised when an edit could not be mapped, so the caller can say why.
    var onRefusal: (EditMapper.Refusal) -> Void = { _ in }

    init(textView: MarkdownTextView) {
        self.textView = textView
        super.init()
    }

    func adopt(index: BlockIndex) {
        self.index = index
    }

    /// Runs a block that writes to the storage without the mirror treating it as a
    /// user edit.
    ///
    /// The flag has to cover every derived write, not only the ones this class makes.
    /// It originally covered only its own, so the view controller's first render
    /// arrived as a giant "user edit" replacing the whole document, was mapped, and
    /// wrote the rendered text back over the source. Headings lost their hashes and
    /// bold lost its asterisks before a single key was pressed.
    func performingDerivedUpdate(_ body: () -> Void) {
        let wasApplying = isApplyingDerivedUpdate
        isApplyingDerivedUpdate = true
        body()
        isApplyingDerivedUpdate = wasApplying
    }

    // MARK: Storage observation

    func textStorage(
        _ textStorage: NSTextStorage,
        didProcessEditing editedMask: NSTextStorageEditActions,
        range editedRange: NSRange,
        changeInLength delta: Int
    ) {
        // Attribute-only edits are spelling underlines, typing attributes and find
        // highlighting. None of them change the document.
        guard editedMask.contains(.editedCharacters) else { return }
        guard !isApplyingDerivedUpdate else { return }
        // While an input method is composing, the storage holds provisional text.
        // Mirroring each provisional state kills the composition, so nothing happens
        // until it is committed.
        guard !textView.hasMarkedText() else { return }

        let oldLength = editedRange.length - delta
        let oldRange = editedRange.location ..< (editedRange.location + max(oldLength, 0))
        let replacement = (textStorage.string as NSString)
            .substring(with: NSRange(location: editedRange.location, length: editedRange.length))

        // Mutating the storage inside its own didProcessEditing is not allowed, so
        // the reconciliation happens on the next turn of the run loop.
        DispatchQueue.main.async { [weak self] in
            self?.reconcile(oldRange: oldRange, replacement: replacement)
        }
    }

    private func reconcile(oldRange: Range<Int>, replacement: String) {
        let source = currentSource()
        switch EditMapper.map(
            renderRange: oldRange, replacement: replacement, index: index, source: source
        ) {
        case .success(let mapped):
            applyEdit(mapped.edit)
            rebuild(caretAtSourceOffset: mapped.caret)

        case .failure(let refusal):
            // The contract: an unmappable edit costs a keystroke, never a document.
            // The source was never touched, so re-rendering from it undoes whatever
            // AppKit put in the storage.
            onRefusal(refusal)
            rebuild(caretAtSourceOffset: nil)
        }
    }

    /// Re-renders from the source and puts the caret back.
    private func rebuild(caretAtSourceOffset caret: Int?) {
        let source = currentSource()
        let rendered = render(source)

        isApplyingDerivedUpdate = true
        textView.textStorage?.setAttributedString(rendered.attributed)
        isApplyingDerivedUpdate = false

        index = rendered.index
        if let caret, let renderOffset = rendered.index.renderOffset(forSource: caret) {
            let length = (textView.string as NSString).length
            textView.setSelectedRange(NSRange(location: min(renderOffset, length), length: 0))
        }
    }

    // MARK: Caret guarding

    /// Nudges the caret out of text the renderer invented.
    ///
    /// Bullets, ordinals and checkboxes are rendered text with no source behind
    /// them, so typing there can only be refused. Rather than let someone put the
    /// caret somewhere that silently swallows keystrokes, the caret is moved to the
    /// first position that can actually be edited.
    func guardedRange(for proposed: NSRange) -> NSRange? {
        guard proposed.length == 0 else { return nil }
        guard let blockIndex = index.blockIndex(forRender: proposed.location) else { return nil }
        let block = index.blocks[blockIndex]
        let entry = index.entries[blockIndex]

        // Attachments occupy one character and cannot be typed into. Put the caret
        // after them so the arrow keys still traverse the document.
        switch block.kind {
        case .table, .mermaid, .displayMath, .thematicBreak, .html:
            return nil
        default: break
        }

        guard let firstRun = entry.runStarts.first, proposed.location < firstRun else { return nil }
        return NSRange(location: firstRun, length: 0)
    }
}
