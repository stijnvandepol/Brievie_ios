import Foundation

/// The pairing code as the user types it from the web page. It is read the way the host's `normalise_code`
/// reads it: upper case, without spaces or "-".
public struct PairingCode: Equatable, Sendable {
    /// `"ABCD-EFGH"`: how the code is shown.
    public let text: String

    /// `"ABCDEFGH"`: what the proof key is derived from.
    public var normalised: String {
        text.replacingOccurrences(of: "-", with: "")
    }

    /// Trims, drops spaces and "-", upper-cases; exactly eight ASCII letters or digits, else `nil`.
    public init?(typed: String) {
        let bytes = typed.trimmingCharacters(in: .whitespacesAndNewlines).utf8
            .filter { $0 != UInt8(ascii: " ") && $0 != UInt8(ascii: "-") }
        guard
            bytes.count == 8, bytes.allSatisfy(PairingPayload.isASCIIAlphanumeric),
            let upper = String(bytes: bytes, encoding: .ascii)?.uppercased()
        else {
            return nil
        }
        text = "\(upper.prefix(4))-\(upper.suffix(4))"
    }
}
