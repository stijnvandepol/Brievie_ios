import Foundation

/// Visible text of this target. The String Catalog (`Resources/Localizable.xcstrings`) is the source of
/// truth in the app; `defaultValue` repeats the Dutch text so that `swift test`, which does not compile
/// catalogs, sees the same words. `AppStringsTests` keeps the two equal.
enum AppStrings {
    static var lockReason: String {
        String(localized: "lock.reason", defaultValue: "Ontgrendel Brievie om je post te zien.", bundle: .module)
    }

    /// After the server refused the device token: revoked on the server, or expired after a long time unused.
    static var sessionRevoked: String {
        String(
            localized: "session.revoked",
            defaultValue: """
                Deze koppeling werkt niet meer: ze is ingetrokken of je hebt Brievie lang niet gebruikt. \
                Koppel dit toestel opnieuw om verder te gaan.
                """,
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

    /// The title of a calendar event without details: on the lock screen, in widgets and for other apps with
    /// calendar access. `%@` is the task type ("Betalen (Brievie)").
    static var calendarNeutralTitleFormat: String {
        String(localized: "calendar.event.neutralTitle", defaultValue: "%@ (Brievie)", bundle: .module)
    }

    /// The name of a workspace's calendar; `%@` is the workspace's name.
    static var calendarNameFormat: String {
        String(localized: "calendar.name", defaultValue: "Brievie – %@", bundle: .module)
    }

    /// On the root screen when the device has no passcode, so the app cannot lock itself.
    static var noPasscode: String {
        String(
            localized: "app.noPasscode",
            defaultValue: "Dit apparaat heeft geen toegangscode. Stel een toegangscode in om je post te beschermen.",
            bundle: .module
        )
    }

    static var genericError: String {
        String(localized: "error.generic", defaultValue: "Er ging iets mis. Probeer het opnieuw.", bundle: .module)
    }
}
