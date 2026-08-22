import AppKit

/// Every colour, size and spacing the renderer uses. Nothing downstream
/// hardcodes a colour or a point size; a guard test enforces that.
///
/// This lives in MarkerRender rather than the app target because the Quick Look
/// extension renders documents too and must not link app code to do it.
public struct MarkerTheme: Sendable {

    public enum Appearance: String, Sendable, CaseIterable {
        case glass, dark, light
    }

    public struct Colors: Sendable {
        public var background: NSColor
        public var text: NSColor
        public var secondaryText: NSColor
        public var heading: NSColor
        public var link: NSColor
        public var rule: NSColor
        public var codeBackground: NSColor
        public var codeBorder: NSColor
        public var quoteBar: NSColor
        public var tableBorder: NSColor
        public var tableHeaderBackground: NSColor
    }

    public struct Metrics: Sendable {
        /// Body point size at zoom 1.0. Every other size is derived from it, so
        /// zooming is one multiply rather than a table of magic numbers.
        public var basePointSize: CGFloat
        public var contentWidth: CGFloat
        public var pageInset: CGFloat
        public var paragraphSpacing: CGFloat
        public var blockSpacing: CGFloat
        public var codeCornerRadius: CGFloat
    }

    public var appearance: Appearance
    public var colors: Colors
    public var metrics: Metrics
    public var zoom: CGFloat

    public var isDark: Bool { appearance != .light }

    // MARK: Fonts

    /// Heading sizes as multiples of the body size, h1 through h6.
    private static let headingScale: [CGFloat] = [2.0, 1.6, 1.32, 1.14, 1.0, 0.9]

    public var bodyPointSize: CGFloat { metrics.basePointSize * zoom }

    public func bodyFont() -> NSFont {
        .systemFont(ofSize: bodyPointSize)
    }

    public func headingFont(level: Int) -> NSFont {
        let scale = Self.headingScale[min(max(level, 1), 6) - 1]
        let size = bodyPointSize * scale
        // Optical sizing: large headings want tighter tracking than body text,
        // and the system face handles that when asked for a bold display weight.
        return .systemFont(ofSize: size, weight: level <= 2 ? .bold : .semibold)
    }

    public func monoFont(scale: CGFloat = 0.92) -> NSFont {
        .monospacedSystemFont(ofSize: bodyPointSize * scale, weight: .regular)
    }

    // MARK: Presets

    public static func standard(_ appearance: Appearance, zoom: CGFloat = 1.0) -> MarkerTheme {
        MarkerTheme(
            appearance: appearance,
            colors: appearance == .light ? .lightPalette : .darkPalette,
            metrics: .standard,
            zoom: zoom
        )
    }

    /// Same theme at a new zoom factor. Re-rendering through this is what keeps
    /// text crisp at 3x instead of scaling a rasterised layer.
    public func scaled(to zoom: CGFloat) -> MarkerTheme {
        var copy = self
        copy.zoom = zoom
        return copy
    }
}

extension MarkerTheme.Metrics {
    public static let standard = MarkerTheme.Metrics(
        basePointSize: 15,
        contentWidth: 760,
        pageInset: 40,
        paragraphSpacing: 12,
        blockSpacing: 20,
        codeCornerRadius: 8
    )
}

extension MarkerTheme.Colors {
    public static let lightPalette = MarkerTheme.Colors(
        background: NSColor(srgbRed: 1.00, green: 1.00, blue: 1.00, alpha: 1),
        text: NSColor(srgbRed: 0.11, green: 0.12, blue: 0.13, alpha: 1),
        secondaryText: NSColor(srgbRed: 0.42, green: 0.44, blue: 0.47, alpha: 1),
        heading: NSColor(srgbRed: 0.05, green: 0.06, blue: 0.07, alpha: 1),
        link: NSColor(srgbRed: 0.00, green: 0.40, blue: 0.85, alpha: 1),
        rule: NSColor(srgbRed: 0.87, green: 0.88, blue: 0.90, alpha: 1),
        codeBackground: NSColor(srgbRed: 0.96, green: 0.965, blue: 0.975, alpha: 1),
        codeBorder: NSColor(srgbRed: 0.90, green: 0.91, blue: 0.93, alpha: 1),
        quoteBar: NSColor(srgbRed: 0.80, green: 0.82, blue: 0.85, alpha: 1),
        tableBorder: NSColor(srgbRed: 0.86, green: 0.87, blue: 0.89, alpha: 1),
        tableHeaderBackground: NSColor(srgbRed: 0.97, green: 0.975, blue: 0.98, alpha: 1)
    )

    public static let darkPalette = MarkerTheme.Colors(
        background: NSColor(srgbRed: 0.09, green: 0.09, blue: 0.10, alpha: 1),
        text: NSColor(srgbRed: 0.90, green: 0.91, blue: 0.92, alpha: 1),
        secondaryText: NSColor(srgbRed: 0.60, green: 0.62, blue: 0.65, alpha: 1),
        heading: NSColor(srgbRed: 0.97, green: 0.97, blue: 0.98, alpha: 1),
        link: NSColor(srgbRed: 0.40, green: 0.68, blue: 1.00, alpha: 1),
        rule: NSColor(srgbRed: 0.22, green: 0.23, blue: 0.25, alpha: 1),
        codeBackground: NSColor(srgbRed: 0.13, green: 0.135, blue: 0.15, alpha: 1),
        codeBorder: NSColor(srgbRed: 0.20, green: 0.21, blue: 0.23, alpha: 1),
        quoteBar: NSColor(srgbRed: 0.30, green: 0.32, blue: 0.35, alpha: 1),
        tableBorder: NSColor(srgbRed: 0.24, green: 0.25, blue: 0.27, alpha: 1),
        tableHeaderBackground: NSColor(srgbRed: 0.14, green: 0.145, blue: 0.16, alpha: 1)
    )
}
