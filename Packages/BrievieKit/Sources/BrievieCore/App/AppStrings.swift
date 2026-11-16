import Foundation

/// Visible text of this target. The String Catalog (`Resources/Localizable.xcstrings`) is the source of
/// truth in the app; `defaultValue` repeats the Dutch text so that `swift test`, which does not compile
/// catalogs, sees the same words. `AppStringsTests` keeps the two equal.
enum AppStrings {
    static var lockReason: String {
        String(localized: "lock.reason", defaultValue: "Ontgrendel Brievie om je post te zien.", bundle: .module)
    }

    static var sessionRevoked: String {
        String(
            localized: "session.revoked",
            defaultValue: "Dit apparaat is ontkoppeld. Koppel het opnieuw om verder te gaan.",
            bundle: .module
        )
    }

    /// After unpairing, when the server could not be told (offline, no answer in time, refused).
    static var serverStillKnowsDevice: String {
        String(
            localized: "unpair.serverStillKnowsDevice",
            defaultValue: "Deze telefoon staat nog als apparaat op de server. Trek hem daar in onder Apparaten.",
            bundle: .module
        )
    }

    /// The last line of a calendar event's notes.
    static var calendarNotesFooter: String {
        String(localized: "calendar.notes.footer", defaultValue: "Uit Brievie", bundle: .module)
    }

    /// The name of a workspace's calendar; `%@` is the workspace's name.
    static var calendarNameFormat: String {
        String(localized: "calendar.name", defaultValue: "Brievie – %@", bundle: .module)
    }

    static var genericError: String {
        String(localized: "error.generic", defaultValue: "Er ging iets mis. Probeer het opnieuw.", bundle: .module)
    }
}
