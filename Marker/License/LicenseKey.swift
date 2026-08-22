import CryptoKit
import Foundation

/// An offline licence key: a payload plus an Ed25519 signature over it.
///
/// Offline on purpose. The product promises no account and no server, and a
/// signature check needs neither: the app carries the public key, the private key
/// never leaves the machine that mints licences, and a forged key fails
/// verification without anything being asked over the network.
/// Opted out of the project's default MainActor isolation. Signing and verifying
/// touch only CryptoKit and Foundation, so pinning them to the main actor would be
/// a lie about where they can run and would make them untestable off it.
public nonisolated struct LicenseKey: Equatable, Sendable {

    public struct Payload: Equatable, Sendable {
        public var name: String
        public var issued: Date

        /// `name|unix-seconds`. Deliberately boring: it is signed, so it needs to be
        /// unambiguous rather than compact, and a pipe cannot appear in a name we
        /// mint because the tool rejects it.
        var canonical: String {
            "\(name)|\(Int(issued.timeIntervalSince1970))"
        }

        init?(canonical: String) {
            let parts = canonical.split(separator: "|", maxSplits: 1).map(String.init)
            guard parts.count == 2, let seconds = TimeInterval(parts[1]), !parts[0].isEmpty else {
                return nil
            }
            name = parts[0]
            issued = Date(timeIntervalSince1970: seconds)
        }

        public init(name: String, issued: Date) {
            self.name = name
            self.issued = issued
        }
    }

    public var payload: Payload
    public var signature: Data

    /// The key as the user sees it: two base32 blobs, dot separated, then broken
    /// into groups of eight so it can be read back over the phone if it has to be.
    ///
    /// Base32 rather than base64url, and the reason is a bug this had first: the
    /// base64url alphabet contains `-`, which was also the group separator, so
    /// stripping the separators on the way back in destroyed the encoding. Base32 is
    /// A to Z and 2 to 7 only, so no separator can collide with it, there is no case
    /// to get wrong, and the ambiguous glyph pairs are absent.
    public var formatted: String {
        let body = Self.base32(Data(payload.canonical.utf8))
            + "." + Self.base32(signature)
        return stride(from: 0, to: body.count, by: 8).map { offset in
            let start = body.index(body.startIndex, offsetBy: offset)
            let end = body.index(start, offsetBy: min(8, body.count - offset))
            return String(body[start ..< end])
        }.joined(separator: "-")
    }

    // MARK: Verification

    public enum Failure: Error, Equatable {
        case malformed
        case signatureDoesNotMatch
    }

    /// Parses and verifies in one step, because a key that parses but does not
    /// verify is not a licence and there is no useful state in between.
    public static func verify(_ text: String, publicKey: Data) throws -> LicenseKey {
        let compact = text
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: " ", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let parts = compact.split(separator: ".", maxSplits: 1).map(String.init)
        guard parts.count == 2,
              let payloadData = decodeBase32(parts[0]),
              let signature = decodeBase32(parts[1]),
              let canonical = String(data: payloadData, encoding: .utf8),
              let payload = Payload(canonical: canonical)
        else { throw Failure.malformed }

        guard let key = try? Curve25519.Signing.PublicKey(rawRepresentation: publicKey),
              key.isValidSignature(signature, for: payloadData)
        else { throw Failure.signatureDoesNotMatch }

        return LicenseKey(payload: payload, signature: signature)
    }

    public static func sign(_ payload: Payload, privateKey: Data) throws -> LicenseKey {
        let key = try Curve25519.Signing.PrivateKey(rawRepresentation: privateKey)
        let signature = try key.signature(for: Data(payload.canonical.utf8))
        return LicenseKey(payload: payload, signature: signature)
    }

    // MARK: base32

    /// RFC 4648 base32, unpadded. Uppercase letters and the digits 2 to 7, so a key
    /// contains nothing a mail client rewrites and nothing a reader can confuse: no
    /// 0 against O, no 1 against l, no case to get wrong.
    static let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567")

    static func base32(_ data: Data) -> String {
        var output = ""
        var buffer = 0
        var bits = 0
        for byte in data {
            buffer = (buffer << 8) | Int(byte)
            bits += 8
            while bits >= 5 {
                output.append(alphabet[(buffer >> (bits - 5)) & 31])
                bits -= 5
            }
        }
        if bits > 0 {
            output.append(alphabet[(buffer << (5 - bits)) & 31])
        }
        return output
    }

    static func decodeBase32(_ text: String) -> Data? {
        var lookup: [Character: Int] = [:]
        for (index, character) in alphabet.enumerated() { lookup[character] = index }

        var bytes: [UInt8] = []
        var buffer = 0
        var bits = 0
        for character in text.uppercased() {
            guard let value = lookup[character] else { return nil }
            buffer = (buffer << 5) | value
            bits += 5
            if bits >= 8 {
                bytes.append(UInt8((buffer >> (bits - 8)) & 0xFF))
                bits -= 8
            }
        }
        guard !bytes.isEmpty else { return nil }
        return Data(bytes)
    }
}
