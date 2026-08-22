// Mints a Marker licence key.
//
//   swift Scripts/make-license.swift "Customer Name"
//
// The signing key lives in Scripts/.license-signing-key, which is gitignored and
// must never be committed: anyone holding it can mint licences. The public half is
// compiled into the app in Marker/License/LicenseStore.swift.
import CryptoKit
import Foundation

let arguments = Array(CommandLine.arguments.dropFirst())
guard let name = arguments.first, !name.isEmpty, !name.contains("|") else {
    FileHandle.standardError.write(Data("usage: make-license.swift \"Customer Name\"\n".utf8))
    exit(2)
}

let scriptDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let keyPath = scriptDirectory.appendingPathComponent(".license-signing-key")

let privateKey: Curve25519.Signing.PrivateKey
if let stored = try? String(contentsOf: keyPath, encoding: .utf8),
   let raw = Data(base64Encoded: stored.trimmingCharacters(in: .whitespacesAndNewlines)),
   let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: raw) {
    privateKey = key
} else {
    FileHandle.standardError.write(Data("""
    No signing key at \(keyPath.path).
    Put the base64 private key there, or generate a new pair and update
    LicenseStore.publicKey to match. Changing the pair invalidates every licence
    already issued.

    """.utf8))
    exit(1)
}

let canonical = "\(name)|\(Int(Date().timeIntervalSince1970))"
let signature = try privateKey.signature(for: Data(canonical.utf8))

/// RFC 4648 base32, unpadded, matching LicenseKey.base32. Base64url was tried and
/// rejected: its alphabet contains the same `-` used to group the key, so stripping
/// the groups on the way back in destroyed the encoding.
func base32(_ data: Data) -> String {
    let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567")
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
    if bits > 0 { output.append(alphabet[(buffer << (5 - bits)) & 31]) }
    return output
}

let body = base32(Data(canonical.utf8)) + "." + base32(signature)
let grouped = stride(from: 0, to: body.count, by: 8).map { offset -> String in
    let start = body.index(body.startIndex, offsetBy: offset)
    let end = body.index(start, offsetBy: min(8, body.count - offset))
    return String(body[start ..< end])
}.joined(separator: "-")

print(grouped)
