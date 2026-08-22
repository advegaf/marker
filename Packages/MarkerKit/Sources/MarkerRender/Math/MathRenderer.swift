import AppKit
import SwiftMath

/// LaTeX to an image, with a cache.
///
/// SwiftMath ships `MTMathImage`, so math never needs a live view. That is what
/// lets a formula be a plain `NSTextAttachment` and therefore work identically in
/// the window, in Quick Look, in PDF export and in the offscreen harness.
public enum MathRenderer {

    /// Content addressed on everything that changes the pixels. Re-rendering the
    /// same formula on every keystroke would otherwise dominate typing cost, since
    /// the whole document is rebuilt on each edit.
    private struct Key: Hashable {
        let latex: String
        let pointSize: CGFloat
        let colorDescription: String
        let display: Bool
    }

    private static let cache = NSCache<NSString, NSImage>()

    public struct Rendered {
        public let image: NSImage
        /// Distance from the image's bottom edge down to the text baseline, so an
        /// inline formula sits on the line rather than floating above it.
        public let descent: CGFloat
    }

    public static func render(
        latex: String,
        pointSize: CGFloat,
        color: NSColor,
        display: Bool
    ) -> Rendered? {
        let trimmed = latex.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let key = Key(
            latex: trimmed,
            pointSize: pointSize,
            colorDescription: color.description,
            display: display
        ) as Key
        let cacheKey = "\(key.hashValue)" as NSString
        if let cached = cache.object(forKey: cacheKey) {
            return Rendered(image: cached, descent: descent(of: cached, pointSize: pointSize, display: display))
        }

        let math = MTMathImage(
            latex: trimmed,
            fontSize: pointSize,
            textColor: color,
            labelMode: display ? .display : .text,
            textAlignment: display ? .center : .left
        )
        let (error, image) = math.asImage()
        // Malformed LaTeX returns an error rather than throwing. The caller falls
        // back to showing the source, which is more useful to someone fixing a
        // formula than a blank space would be.
        guard error == nil, let image else { return nil }

        cache.setObject(image, forKey: cacheKey)
        return Rendered(image: image, descent: descent(of: image, pointSize: pointSize, display: display))
    }

    /// SwiftMath centres the line inside the image it returns, so the baseline sits
    /// at the vertical middle rather than at the bottom. Display math is centred in
    /// its own block and does not need the correction.
    private static func descent(of image: NSImage, pointSize: CGFloat, display: Bool) -> CGFloat {
        display ? 0 : (image.size.height - pointSize * 0.72) / 2
    }
}
