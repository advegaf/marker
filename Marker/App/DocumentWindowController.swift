import AppKit
import MarkerRender

final class DocumentWindowController: NSWindowController {

    private let viewController: DocumentViewController
    private var toolbar: DocumentToolbar!

    init(document: MarkerDocument) {
        viewController = DocumentViewController(document: document)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 700),
            // fullSizeContentView stays. Dropping it gave Liquid Glass an opaque
            // title bar sitting on a translucent page, which is a harder seam than
            // the thing it was meant to fix. Content passing under a translucent
            // title bar is what macOS 26 does; AppKit insets the scroll view so
            // nothing overlaps at rest, and only a scrolled page shows through.
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        // Not a transparent titlebar. With fullSizeContentView and nothing behind
        // the title, scrolled text draws straight through it and collides with the
        // filename. The unified toolbar gives the titlebar its own material.
        window.titlebarAppearsTransparent = false
        window.titleVisibility = .visible
        window.toolbarStyle = .unified
        window.contentViewController = viewController
        window.minSize = NSSize(width: 420, height: 320)
        // Assigning a contentViewController resizes the window to that view's fitting
        // size, and a constraint-free scroll view fits at 1x1. Set the size back after.
        window.setContentSize(NSSize(width: 900, height: 700))
        window.setFrameAutosaveName("MarkerDocumentWindow")
        window.center()

        super.init(window: window)
        viewController.applyAppearance()
        toolbar = DocumentToolbar(controller: viewController)
        window.toolbar = toolbar.makeToolbar()
        viewController.onEditModeChange = { [weak self] in self?.toolbar.syncEditItem() }
        // A harness run must not have its evidence polluted by windows macOS restored
        // from a previous session, and must not leave its own behind for the next run.
        if WindowSnapshot.isRequested { window.isRestorable = false }
        // Do not set `document` here. NSDocument.addWindowController does it, and
        // assigning it first leaves the controller unregistered, so the document
        // drops it and the window deallocates before it is ever shown.
        shouldCascadeWindows = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("unavailable") }

    /// Hands the harness the window and the controller for the document it asked for,
    /// rather than whichever window happened to be constructed first.
    func captureForHarness() {
        guard let window else { return }
        WindowSnapshot.captureThenExit(controller: viewController, window: window)
    }
}
