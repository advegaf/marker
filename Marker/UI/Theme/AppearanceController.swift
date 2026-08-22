import AppKit
import MarkerRender

/// Owns the one appearance choice and hands out themes built from it.
///
/// Liquid Glass is deliberately chrome only: the document background stays a
/// plain colour. Vibrancy is composited by the window server against whatever
/// sits behind the window, so a glass page body captures as transparent in the
/// offscreen screenshot harness and reads as unreadable over a busy desktop.
public final class AppearanceController {

    private static let defaultsKey = "MarkerAppearance"

    public private(set) var appearance: MarkerTheme.Appearance

    public init() {
        let stored = UserDefaults.standard.string(forKey: Self.defaultsKey)
        let forced = ProcessInfo.processInfo.environment["MARKER_THEME"]
        appearance = (forced ?? stored).flatMap(MarkerTheme.Appearance.init(rawValue:)) ?? .glass
    }

    public func theme(zoom: CGFloat = 1.0) -> MarkerTheme {
        .standard(appearance, zoom: zoom)
    }

    public func set(_ new: MarkerTheme.Appearance) {
        guard new != appearance else { return }
        appearance = new
        UserDefaults.standard.set(new.rawValue, forKey: Self.defaultsKey)
        applyToApplication()
        NotificationCenter.default.post(name: .markerAppearanceDidChange, object: nil)
    }

    public func applyToApplication() {
        NSApp?.appearance = NSAppearance(named: appearance == .light ? .aqua : .darkAqua)
    }
}

extension Notification.Name {
    public static let markerAppearanceDidChange = Notification.Name("MarkerAppearanceDidChange")
}
