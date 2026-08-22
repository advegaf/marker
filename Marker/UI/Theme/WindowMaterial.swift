import AppKit
import MarkerRender

/// Installs or removes the translucent window background for Liquid Glass.
///
/// `NSVisualEffectView` with a standard material, not `NSGlassEffectView`. Apple's
/// rule, and the skill's first one, is that Liquid Glass is the functional layer
/// above content: toolbars, sheets, popovers, menus, all of which macOS 26 gives
/// us on recompile. A document page is the content layer, so a translucent window
/// there is a standard material. Reaching for the glass view here would be exactly
/// the decoration case the guidance rules out.
enum WindowMaterial {

    /// A subclass rather than a tag, because `NSView.tag` is read only and a marker
    /// subclass is clearer than reaching for `accessibilityIdentifier` anyway.
    private final class MarkerBackdrop: NSVisualEffectView {}

    static func apply(_ theme: MarkerTheme, to contentView: NSView) {
        contentView.subviews.compactMap { $0 as? MarkerBackdrop }.forEach { $0.removeFromSuperview() }
        guard theme.isTranslucent else { return }

        let effect = MarkerBackdrop(frame: contentView.bounds)
        effect.autoresizingMask = [.width, .height]
        effect.material = .underWindowBackground
        effect.blendingMode = .behindWindow
        // Without this the material stays lit when the window is not focused, which
        // reads as a bug next to every other Mac window.
        effect.state = .followsWindowActiveState
        contentView.addSubview(effect, positioned: .below, relativeTo: nil)
    }
}
