import AppKit
import MarkerRender

/// A strip across the top of the document saying the file changed underneath.
///
/// Not an alert. An alert would block the window and demand an answer before the
/// reader can even look at what they were reading, and the honest answer is often
/// "let me see first". The banner sits above the page and waits.
final class ReloadBanner: NSView {

    private let label = NSTextField(labelWithString: "")
    private let primary = NSButton()
    private let secondary = NSButton()
    private var onPrimary: (() -> Void)?
    private var onSecondary: (() -> Void)?

    static let height: CGFloat = 44

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true

        label.lineBreakMode = .byTruncatingTail
        label.font = .systemFont(ofSize: NSFont.systemFontSize)

        for button in [primary, secondary] {
            button.bezelStyle = .rounded
            button.controlSize = .regular
            button.target = self
        }
        primary.action = #selector(primaryPressed)
        secondary.action = #selector(secondaryPressed)
        primary.keyEquivalent = "\r"

        let stack = NSStackView(views: [label, NSView(), secondary, primary])
        stack.orientation = .horizontal
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 16, bottom: 0, right: 16)
        stack.alignment = .centerY
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("unavailable") }

    func show(
        message: String,
        primaryTitle: String,
        secondaryTitle: String,
        theme: MarkerTheme,
        onPrimary: @escaping () -> Void,
        onSecondary: @escaping () -> Void
    ) {
        label.stringValue = message
        label.textColor = theme.colors.text
        primary.title = primaryTitle
        secondary.title = secondaryTitle
        self.onPrimary = onPrimary
        self.onSecondary = onSecondary
        layer?.backgroundColor = theme.colors.codeBackground.cgColor
        isHidden = false
    }

    func hide() {
        isHidden = true
        onPrimary = nil
        onSecondary = nil
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        // A hairline along the bottom, so the strip reads as chrome sitting on the
        // page rather than as part of the document.
        NSColor.separatorColor.setFill()
        NSRect(x: 0, y: bounds.height - 1, width: bounds.width, height: 1).fill()
    }

    @objc private func primaryPressed() {
        let action = onPrimary
        hide()
        action?()
    }

    @objc private func secondaryPressed() {
        let action = onSecondary
        hide()
        action?()
    }
}
