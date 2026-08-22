import Foundation

/// Owns the document's zoom factor.
///
/// Kept as a separate type because zoom is arithmetic, not view code, and the
/// step and clamp behaviour is worth testing without an app running.
public final class ZoomController {

    public static let minScale: CGFloat = 0.5
    public static let maxScale: CGFloat = 3.0

    /// Multiplicative steps, so zooming in then out returns exactly where it started.
    private static let step: CGFloat = 1.1

    private static let defaultsKey = "MarkerZoom"

    public private(set) var scale: CGFloat

    public init(initial: CGFloat? = nil) {
        let forced = ProcessInfo.processInfo.environment["MARKER_ZOOM"]
            .flatMap { Double($0) }
            .map { CGFloat($0) }
        let stored = (UserDefaults.standard.object(forKey: Self.defaultsKey) as? Double)
            .map { CGFloat($0) }
        scale = Self.clamp(initial ?? forced ?? stored ?? 1.0)
    }

    public static func clamp(_ value: CGFloat) -> CGFloat {
        min(max(value, minScale), maxScale)
    }

    @discardableResult public func stepUp() -> Bool { set(scale * Self.step) }
    @discardableResult public func stepDown() -> Bool { set(scale / Self.step) }
    @discardableResult public func reset() -> Bool { set(1.0) }

    /// Folds a finished pinch gesture's magnification into the persistent factor.
    @discardableResult public func fold(gesture: CGFloat) -> Bool { set(scale * gesture) }

    @discardableResult private func set(_ new: CGFloat) -> Bool {
        let clamped = Self.clamp(new)
        guard abs(clamped - scale) > 0.0001 else { return false }
        scale = clamped
        UserDefaults.standard.set(Double(clamped), forKey: Self.defaultsKey)
        return true
    }
}
