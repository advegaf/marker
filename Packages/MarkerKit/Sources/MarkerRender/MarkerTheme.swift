import AppKit
import MarkerCore

/// Every colour, size and spacing the renderer uses. Nothing downstream
/// hardcodes a colour or a point size; a guard test enforces that.
///
/// This lives in MarkerRender rather than the app target because the Quick Look
/// extension renders documents too and must not link app code to do it.
public struct MarkerTheme: Sendable {

    public enum Appearance: String, Sendable, CaseIterable, Hashable {
        case glass, dark, light
    }

    /// Syntax colours, one per `TokenKind`.
    ///
    /// The palette is GitHub's, because it is the one most people already read code
    /// in and it has been contrast tested far more thoroughly than anything invented
    /// here would be.
    public struct Syntax: Sendable {
        public var keyword: NSColor
        public var type: NSColor
        public var string: NSColor
        public var number: NSColor
        public var comment: NSColor
        public var punctuation: NSColor
        public var attribute: NSColor

        public func color(for kind: TokenKind, plain: NSColor) -> NSColor {
            switch kind {
            case .plain: return plain
            case .keyword: return keyword
            case .type: return type
            case .string: return string
            case .number: return number
            case .comment: return comment
            case .punctuation: return punctuation
            case .attribute: return attribute
            }
        }
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
        public var syntax: Syntax
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

    /// Resolved, not derived from `appearance`. Liquid Glass follows the system, so
    /// it can be either, and computing this from the enum is what made glass and
    /// dark identical in the first place.
    public var isDark: Bool

    /// Whether the window is drawing over a translucent material. Glass only, and
    /// only when Reduce Transparency is off.
    public var isTranslucent: Bool

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

    /// The one place the three choices turn into a concrete theme.
    ///
    /// Liquid Glass is a material, not a palette. It takes its colours from whatever
    /// the system is set to and makes the window translucent; Dark and Light force a
    /// palette and stay opaque. Modelling glass as a third palette is what made it
    /// indistinguishable from Dark.
    public static func resolve(
        appearance: Appearance,
        systemIsDark: Bool,
        reduceTransparency: Bool = false,
        zoom: CGFloat = 1.0
    ) -> MarkerTheme {
        let dark: Bool
        switch appearance {
        case .glass: dark = systemIsDark
        case .dark: dark = true
        case .light: dark = false
        }
        let translucent = appearance == .glass && !reduceTransparency
        var colors = dark ? Colors.darkPalette : Colors.lightPalette
        if translucent { colors = colors.overTranslucentBackground(isDark: dark) }

        return MarkerTheme(
            appearance: appearance,
            colors: colors,
            metrics: .standard,
            zoom: zoom,
            isDark: dark,
            isTranslucent: translucent
        )
    }

    /// Opaque, for callers with no window to ask: the Quick Look extension, the
    /// offscreen renderer, and tests.
    public static func standard(_ appearance: Appearance, zoom: CGFloat = 1.0) -> MarkerTheme {
        resolve(
            appearance: appearance,
            systemIsDark: appearance != .light,
            reduceTransparency: true,
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

    /// Adjusted for drawing over a translucent window material.
    ///
    /// A material samples the desktop behind it, so contrast is no longer something
    /// the palette controls on its own. Text and headings go fully opaque, and the
    /// panels that were tints of the page get real fills, because a tint of
    /// something translucent is just more translucency.
    func overTranslucentBackground(isDark: Bool) -> MarkerTheme.Colors {
        var copy = self
        copy.background = .clear
        copy.text = isDark
            ? NSColor(srgbRed: 0.96, green: 0.97, blue: 0.98, alpha: 1)
            : NSColor(srgbRed: 0.06, green: 0.07, blue: 0.08, alpha: 1)
        copy.heading = copy.text
        copy.secondaryText = isDark
            ? NSColor(srgbRed: 0.74, green: 0.76, blue: 0.79, alpha: 1)
            : NSColor(srgbRed: 0.30, green: 0.32, blue: 0.35, alpha: 1)
        // An overlay of the foreground, not a darker fill. The same colour is used
        // for block panels and for inline code chips, and a dark fill over a
        // translucent ground reads as a hard black block punched into the page.
        copy.codeBackground = isDark
            ? NSColor(srgbRed: 1.00, green: 1.00, blue: 1.00, alpha: 0.10)
            : NSColor(srgbRed: 0.00, green: 0.00, blue: 0.00, alpha: 0.055)
        copy.codeBorder = isDark
            ? NSColor(srgbRed: 1.00, green: 1.00, blue: 1.00, alpha: 0.16)
            : NSColor(srgbRed: 0.00, green: 0.00, blue: 0.00, alpha: 0.12)
        copy.quoteBar = isDark
            ? NSColor(srgbRed: 1.00, green: 1.00, blue: 1.00, alpha: 0.36)
            : NSColor(srgbRed: 0.00, green: 0.00, blue: 0.00, alpha: 0.28)
        copy.rule = copy.codeBorder
        copy.tableHeaderBackground = copy.codeBackground
        return copy
    }

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
        tableHeaderBackground: NSColor(srgbRed: 0.97, green: 0.975, blue: 0.98, alpha: 1),
        syntax: MarkerTheme.Syntax(
            keyword: NSColor(srgbRed: 0.81, green: 0.13, blue: 0.18, alpha: 1),
            type: NSColor(srgbRed: 0.58, green: 0.22, blue: 0.00, alpha: 1),
            string: NSColor(srgbRed: 0.04, green: 0.19, blue: 0.41, alpha: 1),
            number: NSColor(srgbRed: 0.02, green: 0.31, blue: 0.68, alpha: 1),
            comment: NSColor(srgbRed: 0.43, green: 0.46, blue: 0.51, alpha: 1),
            punctuation: NSColor(srgbRed: 0.24, green: 0.26, blue: 0.29, alpha: 1),
            attribute: NSColor(srgbRed: 0.51, green: 0.31, blue: 0.87, alpha: 1)
        )
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
        tableHeaderBackground: NSColor(srgbRed: 0.14, green: 0.145, blue: 0.16, alpha: 1),
        syntax: MarkerTheme.Syntax(
            keyword: NSColor(srgbRed: 1.00, green: 0.48, blue: 0.45, alpha: 1),
            type: NSColor(srgbRed: 1.00, green: 0.65, blue: 0.34, alpha: 1),
            string: NSColor(srgbRed: 0.65, green: 0.84, blue: 1.00, alpha: 1),
            number: NSColor(srgbRed: 0.47, green: 0.75, blue: 1.00, alpha: 1),
            comment: NSColor(srgbRed: 0.55, green: 0.58, blue: 0.62, alpha: 1),
            punctuation: NSColor(srgbRed: 0.79, green: 0.82, blue: 0.85, alpha: 1),
            attribute: NSColor(srgbRed: 0.82, green: 0.66, blue: 1.00, alpha: 1)
        )
    )
}
