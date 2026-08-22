import AppKit
import MarkerCore

/// Renders a document to a PNG without ever putting a window on screen.
///
/// This is the QA loop's instrument, so it is built to be boring and repeatable:
/// same input, byte-identical output, no Screen Recording permission, no window
/// server race. Three details carry that, and each one is a silent-failure trap
/// if skipped. They are called out at their call sites below.
public enum OffscreenRenderer {

    public struct Options: Sendable {
        public var width: CGFloat
        public var maxHeight: CGFloat
        public var scale: CGFloat

        public init(width: CGFloat = 1200, maxHeight: CGFloat = 20000, scale: CGFloat = 2) {
            self.width = width
            self.maxHeight = maxHeight
            self.scale = scale
        }
    }

    public static func png(
        of source: MarkdownSource,
        theme: MarkerTheme,
        options: Options = Options()
    ) -> Data? {
        let attributed = DocumentRenderer(theme: theme, mode: .image).render(source)

        let textView = MarkdownTextView(theme: theme)
        textView.frame = NSRect(x: 0, y: 0, width: options.width, height: options.maxHeight)
        // Trap 1 used to live here as a private copy of ensure-layout-then-size.
        // It is now setContent's job, shared with the window and the Quick Look
        // extension, because those two skipping it is what broke scrolling.
        textView.setContent(attributed, theme: theme, availableWidth: options.width)

        let height = min(max(textView.frame.height, 64), options.maxHeight)
        textView.frame = NSRect(x: 0, y: 0, width: options.width, height: height)

        // Trap 2: a view outside a window resolves dynamic system colours and font
        // metrics against the wrong appearance. The window is needed even though it
        // is never ordered front.
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: options.width, height: height),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.appearance = NSAppearance(named: theme.isDark ? .darkAqua : .aqua)
        let container = NSView(frame: NSRect(x: 0, y: 0, width: options.width, height: height))
        container.wantsLayer = true
        container.layer?.backgroundColor = theme.colors.background.cgColor
        container.addSubview(textView)
        window.contentView = container
        container.layoutSubtreeIfNeeded()

        // Trap 3: bitmapImageRepForCachingDisplay inherits the window's
        // backingScaleFactor, and an unordered window can report 1.0. Allocating the
        // pixels explicitly and setting rep.size to the point size forces 2x on
        // every machine, so evidence PNGs compare across runs.
        let pixelWidth = Int(options.width * options.scale)
        let pixelHeight = Int(height * options.scale)
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelWidth, pixelsHigh: pixelHeight,
            bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0
        ) else { return nil }
        rep.size = NSSize(width: options.width, height: height)

        container.cacheDisplay(in: container.bounds, to: rep)
        return rep.representation(using: .png, properties: [:])
    }
}
