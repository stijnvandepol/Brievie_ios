import Foundation

/// The app version every request to the server carries (D 7.1), so the server's device list can show it.
public enum AppVersionHeader {
    public static let name = "X-Brievie-App-Version"
    /// The server accepts at most this many characters and ignores anything longer.
    static let maximumLength = 50

    /// `"<short> (<build>)"`, for example `"1.4.0 (12)"`. `nil` when either part is missing or empty, or when the
    /// result is outside what the server accepts (`^[0-9A-Za-z.+()\- ]{1,50}$`): the app sends nothing rather
    /// than a value the server would ignore.
    public static func value(shortVersion: String?, build: String?) -> String? {
        guard let shortVersion, let build, !shortVersion.isEmpty, !build.isEmpty else { return nil }
        let value = "\(shortVersion) (\(build))"
        guard value.utf8.count <= maximumLength, value.utf8.allSatisfy(isAllowed) else { return nil }
        return value
    }

    /// The version of the running app, from `CFBundleShortVersionString` and `CFBundleVersion`.
    public static func current(bundle: Bundle = .main) -> String? {
        value(
            shortVersion: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
            build: bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        )
    }

    private static func isAllowed(_ byte: UInt8) -> Bool {
        switch byte {
        case UInt8(ascii: "0")...UInt8(ascii: "9"),
             UInt8(ascii: "a")...UInt8(ascii: "z"),
             UInt8(ascii: "A")...UInt8(ascii: "Z"),
             UInt8(ascii: "."), UInt8(ascii: "+"), UInt8(ascii: "("), UInt8(ascii: ")"),
             UInt8(ascii: "-"), UInt8(ascii: " "):
            true
        default:
            false
        }
    }
}
