import AppKit
import MarkerRender

/// Owns the one appearance choice and turns it into a concrete theme.
///
/// The important distinction, and the one this class got wrong before: Liquid
/// Glass is a material, not a palette. It follows whatever the system is set to
/// and makes the window translucent. Dark and Light force a palette and stay
/// opaque. Modelling glass as a third palette made it identical to Dark, so the
/// switch appeared to do nothing.
public final class AppearanceController {

    private static let defaultsKey = "MarkerAppearance"

    public private(set) var appearance: MarkerTheme.Appearance

    public init() {
        let stored = UserDefaults.standard.string(forKey: Self.defaultsKey)
        let forced = ProcessInfo.processInfo.environment["MARKER_THEME"]
        appearance = (forced ?? stored).flatMap(MarkerTheme.Appearance.init(rawValue:)) ?? .glass
        // Republished at launch so a fresh install, or a preview taken before the
        // theme was ever changed, still matches the app.
        ThemeBridge.publish(appearance)

        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(accessibilityOptionsChanged),
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil
        )
    }

    deinit { NSWorkspace.shared.notificationCenter.removeObserver(self) }

    // MARK: Resolution

    /// Reduce Transparency turns the translucent window back into an opaque one.
    /// The env override exists so the harness can capture that state without
    /// writing to the user's accessibility settings.
    public var reduceTransparency: Bool {
        if ProcessInfo.processInfo.environment["MARKER_REDUCE_TRANSPARENCY"] != nil { return true }
        return NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
    }

    /// Resolved against a specific view, so the palette follows that view's
    /// effective appearance rather than a global guess. Falls back to the app's own
    /// effective appearance when there is no view yet.
    public func theme(for view: NSView? = nil, zoom: CGFloat = 1.0) -> MarkerTheme {
        let effective = view?.effectiveAppearance ?? NSApp?.effectiveAppearance
        let isDark = effective?.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        return .resolve(
            appearance: appearance,
            systemIsDark: isDark,
            reduceTransparency: reduceTransparency,
            zoom: zoom
        )
    }

    public func set(_ new: MarkerTheme.Appearance) {
        guard new != appearance else { return }
        appearance = new
        UserDefaults.standard.set(new.rawValue, forKey: Self.defaultsKey)
        ThemeBridge.publish(new)
        applyToApplication()
        NotificationCenter.default.post(name: .markerAppearanceDidChange, object: nil)
    }

    /// Glass leaves `NSApp.appearance` nil so the system value survives and can be
    /// read back. Forcing an appearance is what destroyed it before, which is why
    /// glass could never be light.
    public func applyToApplication() {
        switch appearance {
        case .glass: NSApp?.appearance = nil
        case .dark: NSApp?.appearance = NSAppearance(named: .darkAqua)
        case .light: NSApp?.appearance = NSAppearance(named: .aqua)
        }
    }

    @objc private func accessibilityOptionsChanged() {
        // Reduce Transparency flipping must take effect without a relaunch.
        NotificationCenter.default.post(name: .markerAppearanceDidChange, object: nil)
    }
}

extension Notification.Name {
    public static let markerAppearanceDidChange = Notification.Name("MarkerAppearanceDidChange")
}
