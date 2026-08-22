import Foundation

/// Converting between the two coordinate spaces, in one place.
///
/// Rendered text is counted in UTF-16 because that is what AppKit reports; source
/// is counted in UTF-8 because that is what cmark reports. An emoji is two units
/// against four bytes and a CJK character is one against three, so carrying an
/// offset between them unconverted lands mid-character.
///
/// This existed twice, and the copy that was not fixed was the one the app actually
/// called: selecting three CJK characters bolded only the first.
public enum OffsetConversion {

    /// UTF-8 byte offset matching a UTF-16 offset inside `text`.
    ///
    /// Returns nil when the offset lands inside a surrogate pair, which is not a
    /// position a caret can occupy and is not something to round to the nearest.
    public static func utf8Offset(forUTF16 offset: Int, in text: String) -> Int? {
        guard offset >= 0 else { return nil }
        if offset == 0 { return 0 }
        var utf16Seen = 0
        var utf8Seen = 0
        for character in text {
            if utf16Seen == offset { return utf8Seen }
            utf16Seen += character.utf16.count
            utf8Seen += String(character).utf8.count
            if utf16Seen > offset { return nil }
        }
        return utf16Seen == offset ? utf8Seen : nil
    }

    /// UTF-16 offset matching a UTF-8 byte offset inside `text`.
    public static func utf16Offset(forUTF8 offset: Int, in text: String) -> Int? {
        guard offset >= 0 else { return nil }
        if offset == 0 { return 0 }
        var utf16Seen = 0
        var utf8Seen = 0
        for character in text {
            if utf8Seen == offset { return utf16Seen }
            utf8Seen += String(character).utf8.count
            utf16Seen += character.utf16.count
            if utf8Seen > offset { return nil }
        }
        return utf8Seen == offset ? utf16Seen : nil
    }
}
