import AppKit
import MarkerCore

/// Draws a `MermaidScene` into an image.
///
/// The only part of the diagram engine that knows about AppKit. Everything that
/// decides where things go lives in `MarkerCore` and is tested on coordinates.
public enum MermaidRenderer {

    /// The text ruler the layout uses in the app, as opposed to the deterministic
    /// one the tests use.
    public static func measure(fontSize: CGFloat) -> TextMeasure {
        TextMeasure { text, pointSize in
            let font = NSFont.systemFont(ofSize: pointSize)
            let attributed = NSAttributedString(string: text, attributes: [.font: font])
            let bounds = attributed.boundingRect(
                with: CGSize(
                    width: CGFloat.greatestFiniteMagnitude,
                    height: CGFloat.greatestFiniteMagnitude
                ),
                options: [.usesLineFragmentOrigin, .usesFontLeading]
            )
            return CGSize(width: ceil(bounds.width), height: ceil(bounds.height))
        }
    }

    public struct Palette {
        public var nodeFill: NSColor
        public var nodeStroke: NSColor
        public var line: NSColor
        public var text: NSColor
        public var labelBackground: NSColor

        /// Derived from the document theme so a diagram belongs to the page rather
        /// than looking like a pasted screenshot.
        public init(theme: MarkerTheme) {
            nodeFill = theme.colors.codeBackground
            nodeStroke = theme.isDark
                ? theme.colors.secondaryText.withAlphaComponent(0.55)
                : theme.colors.secondaryText.withAlphaComponent(0.45)
            line = theme.colors.secondaryText
            text = theme.colors.text
            labelBackground = theme.colors.background
        }
    }

    public static func image(
        for scene: MermaidScene, theme: MarkerTheme, palette: Palette? = nil
    ) -> NSImage? {
        guard scene.size.width > 1, scene.size.height > 1 else { return nil }
        let palette = palette ?? Palette(theme: theme)

        let image = NSImage(size: scene.size)
        image.lockFocusFlipped(true)
        defer { image.unlockFocus() }

        for shape in scene.shapes { draw(shape, palette: palette) }
        for path in scene.paths { draw(path, palette: palette) }
        for box in scene.labelBackgrounds {
            palette.labelBackground.setFill()
            NSBezierPath(roundedRect: box, xRadius: 3, yRadius: 3).fill()
        }
        for text in scene.texts { draw(text, theme: theme, palette: palette) }

        return image
    }

    // MARK: Shapes

    private static func draw(_ shape: MermaidScene.Shape, palette: Palette) {
        let path = bezier(for: shape)
        if shape.filled {
            palette.nodeFill.setFill()
            path.fill()
        }
        palette.nodeStroke.setStroke()
        apply(shape.stroke, to: path)
        path.stroke()
    }

    private static func bezier(for shape: MermaidScene.Shape) -> NSBezierPath {
        let frame = shape.frame.insetBy(dx: 0.75, dy: 0.75)
        switch shape.kind {
        case .rectangle(let radius):
            let clamped = min(radius, min(frame.width, frame.height) / 2)
            return NSBezierPath(roundedRect: frame, xRadius: clamped, yRadius: clamped)

        case .ellipse:
            return NSBezierPath(ovalIn: frame)

        case .diamond:
            let path = NSBezierPath()
            path.move(to: CGPoint(x: frame.midX, y: frame.minY))
            path.line(to: CGPoint(x: frame.maxX, y: frame.midY))
            path.line(to: CGPoint(x: frame.midX, y: frame.maxY))
            path.line(to: CGPoint(x: frame.minX, y: frame.midY))
            path.close()
            return path

        case .hexagon:
            let notch = min(frame.width * 0.18, frame.height * 0.5)
            let path = NSBezierPath()
            path.move(to: CGPoint(x: frame.minX + notch, y: frame.minY))
            path.line(to: CGPoint(x: frame.maxX - notch, y: frame.minY))
            path.line(to: CGPoint(x: frame.maxX, y: frame.midY))
            path.line(to: CGPoint(x: frame.maxX - notch, y: frame.maxY))
            path.line(to: CGPoint(x: frame.minX + notch, y: frame.maxY))
            path.line(to: CGPoint(x: frame.minX, y: frame.midY))
            path.close()
            return path

        case .subroutine:
            let path = NSBezierPath(rect: frame)
            let inset = min(frame.width * 0.06, 8)
            path.move(to: CGPoint(x: frame.minX + inset, y: frame.minY))
            path.line(to: CGPoint(x: frame.minX + inset, y: frame.maxY))
            path.move(to: CGPoint(x: frame.maxX - inset, y: frame.minY))
            path.line(to: CGPoint(x: frame.maxX - inset, y: frame.maxY))
            return path

        case .cylinder:
            let lip = min(frame.height * 0.16, 12)
            let path = NSBezierPath()
            path.appendOval(in: CGRect(x: frame.minX, y: frame.minY, width: frame.width, height: lip * 2))
            path.move(to: CGPoint(x: frame.minX, y: frame.minY + lip))
            path.line(to: CGPoint(x: frame.minX, y: frame.maxY - lip))
            path.appendArc(
                withCenter: CGPoint(x: frame.midX, y: frame.maxY - lip),
                radius: frame.width / 2, startAngle: 180, endAngle: 0, clockwise: true
            )
            path.move(to: CGPoint(x: frame.maxX, y: frame.minY + lip))
            path.line(to: CGPoint(x: frame.maxX, y: frame.maxY - lip))
            return path

        case .note:
            let fold = min(frame.width * 0.14, 14)
            let path = NSBezierPath()
            path.move(to: CGPoint(x: frame.minX, y: frame.minY))
            path.line(to: CGPoint(x: frame.maxX - fold, y: frame.minY))
            path.line(to: CGPoint(x: frame.maxX, y: frame.minY + fold))
            path.line(to: CGPoint(x: frame.maxX, y: frame.maxY))
            path.line(to: CGPoint(x: frame.minX, y: frame.maxY))
            path.close()
            return path
        }
    }

    // MARK: Paths

    private static func draw(_ path: MermaidScene.Path, palette: Palette) {
        guard path.points.count >= 2 else { return }
        let line = NSBezierPath()
        line.move(to: path.points[0])
        // Rounded corners on the dog-legs, so an orthogonal route reads as a drawn
        // line rather than as a staircase.
        if path.points.count > 2 {
            for index in 1 ..< (path.points.count - 1) {
                let previous = path.points[index - 1]
                let corner = path.points[index]
                let next = path.points[index + 1]
                let radius: CGFloat = 6
                line.line(to: pointBefore(corner, from: previous, by: radius))
                line.curve(
                    to: pointBefore(corner, from: next, by: radius),
                    controlPoint1: corner, controlPoint2: corner
                )
            }
        }
        line.line(to: path.points[path.points.count - 1])

        palette.line.setStroke()
        apply(path.stroke, to: line)
        line.stroke()

        let end = path.points[path.points.count - 1]
        let before = path.points[path.points.count - 2]
        if path.isCrossHead {
            drawCross(at: end, palette: palette)
        } else if path.hasArrowHead {
            drawArrow(at: end, from: before, palette: palette, open: path.isOpenHead)
        }
    }

    private static func pointBefore(_ corner: CGPoint, from other: CGPoint, by radius: CGFloat) -> CGPoint {
        let dx = other.x - corner.x
        let dy = other.y - corner.y
        let length = max(sqrt(dx * dx + dy * dy), 0.001)
        let clamped = min(radius, length / 2)
        return CGPoint(x: corner.x + dx / length * clamped, y: corner.y + dy / length * clamped)
    }

    private static func drawArrow(at tip: CGPoint, from origin: CGPoint, palette: Palette, open: Bool) {
        let angle = atan2(tip.y - origin.y, tip.x - origin.x)
        let length: CGFloat = 9
        let spread: CGFloat = .pi / 7

        let left = CGPoint(
            x: tip.x - length * cos(angle - spread),
            y: tip.y - length * sin(angle - spread)
        )
        let right = CGPoint(
            x: tip.x - length * cos(angle + spread),
            y: tip.y - length * sin(angle + spread)
        )

        let head = NSBezierPath()
        head.move(to: left)
        head.line(to: tip)
        head.line(to: right)
        if open {
            head.lineWidth = 1.5
            palette.line.setStroke()
            head.stroke()
        } else {
            head.close()
            palette.line.setFill()
            head.fill()
        }
    }

    private static func drawCross(at point: CGPoint, palette: Palette) {
        let arm: CGFloat = 5
        let cross = NSBezierPath()
        cross.move(to: CGPoint(x: point.x - arm, y: point.y - arm))
        cross.line(to: CGPoint(x: point.x + arm, y: point.y + arm))
        cross.move(to: CGPoint(x: point.x + arm, y: point.y - arm))
        cross.line(to: CGPoint(x: point.x - arm, y: point.y + arm))
        cross.lineWidth = 1.5
        palette.line.setStroke()
        cross.stroke()
    }

    private static func apply(_ stroke: MermaidScene.Stroke, to path: NSBezierPath) {
        switch stroke {
        case .solid(let width):
            path.lineWidth = width
        case .dashed(let width, let pattern):
            path.lineWidth = width
            path.setLineDash(pattern, count: pattern.count, phase: 0)
        }
    }

    // MARK: Text

    private static func draw(_ text: MermaidScene.Text, theme: MarkerTheme, palette: Palette) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byWordWrapping

        let size: CGFloat
        let weight: NSFont.Weight
        switch text.role {
        case .nodeLabel: size = theme.bodyPointSize * 0.95; weight = .regular
        case .edgeLabel: size = theme.bodyPointSize * 0.8; weight = .regular
        case .participant: size = theme.bodyPointSize * 0.95; weight = .semibold
        case .title: size = theme.bodyPointSize * 1.1; weight = .semibold
        case .note: size = theme.bodyPointSize * 0.8; weight = .regular
        }

        let attributed = NSAttributedString(string: text.string, attributes: [
            .font: NSFont.systemFont(ofSize: size, weight: weight),
            .foregroundColor: text.role == .edgeLabel ? palette.line : palette.text,
            .paragraphStyle: paragraph,
        ])

        // Centred vertically inside its box, which is what a label in a shape means.
        let bounds = attributed.boundingRect(
            with: CGSize(width: text.frame.width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
        let box = CGRect(
            x: text.frame.minX,
            y: text.frame.midY - bounds.height / 2,
            width: text.frame.width,
            height: bounds.height
        )
        attributed.draw(with: box, options: [.usesLineFragmentOrigin, .usesFontLeading])
    }
}
