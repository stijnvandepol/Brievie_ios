import Foundation

/// Visible text of this target. The String Catalog (`Resources/Localizable.xcstrings`) is the source of
/// truth in the app; `defaultValue` repeats the Dutch text so that `swift test`, which does not compile
/// catalogs, sees the same words. `WorkspacesModelTests` keeps the two equal.
enum WorkspaceStrings {
    static let kindHome = String(localized: "workspaces.kind.home", defaultValue: "Thuis", bundle: .module)
    static let kindBusiness = String(localized: "workspaces.kind.business", defaultValue: "Zakelijk", bundle: .module)
    static let kindUnknown = String(localized: "workspaces.kind.unknown", defaultValue: "Werkruimte", bundle: .module)
    static let roleAdmin = String(localized: "workspaces.role.admin", defaultValue: "Beheerder", bundle: .module)
    static let roleMember = String(localized: "workspaces.role.member", defaultValue: "Lid", bundle: .module)
    static let roleViewer = String(localized: "workspaces.role.viewer", defaultValue: "Kijker", bundle: .module)
    static let unreachable = String(
        localized: "workspaces.error.unreachable",
        defaultValue: "We kunnen je Brievie-server niet bereiken. Zit je op hetzelfde netwerk?",
        bundle: .module
    )
    static let notVerified = String(
        localized: "workspaces.error.notVerified",
        defaultValue: """
            We konden niet controleren of dit jouw Brievie-server is. \
            Koppel de app opnieuw als dit blijft gebeuren.
            """,
        bundle: .module
    )
    static let generic = String(
        localized: "error.generic",
        defaultValue: "Er ging iets mis. Probeer het opnieuw.",
        bundle: .module
    )

    static let unpairMessage = String(
        localized: "workspaces.unpair.message",
        defaultValue: """
            Deze telefoon vergeet de koppeling met je Brievie-server. \
            Je kunt daarna opnieuw koppelen met een nieuwe QR-code.
            """,
        bundle: .module
    )

    /// The unpair message when `count` (at least 1) scans still wait to be sent. The catalog has the
    /// singular and plural; the default here is the plural (`swift test` reads no catalogs).
    static func unpairMessageQueued(_ count: Int) -> String {
        String(
            localized: "workspaces.unpair.message.queued",
            defaultValue: """
                Er wachten nog \(count) scans om te versturen. Die scans worden van deze telefoon verwijderd. \
                Je kunt daarna opnieuw koppelen met een nieuwe QR-code.
                """,
            bundle: .module
        )
    }

    /// The second destructive choice in the unpair confirmation, when a calendar switch is on.
    static let unpairRemovingCalendars = String(
        localized: "workspaces.unpair.confirmRemovingCalendars",
        defaultValue: "Ontkoppelen en agenda's verwijderen",
        bundle: .module
    )

    static let calendarNoAccess = String(
        localized: "workspaces.calendar.noAccess",
        defaultValue: "Geef Brievie toegang tot je agenda in Instellingen.",
        bundle: .module
    )

    /// The server has no task list yet (a 1b server): the switch stays off.
    static let calendarTasksNotSupported = String(
        localized: "workspaces.calendar.tasksNotSupported",
        defaultValue: "Deze server kan nog geen taken doorgeven. Werk de server bij.",
        bundle: .module
    )

    /// Under a switched-off calendar switch, when "Verwijderen" found events of the user in the calendar.
    static let calendarKeptForUserEvents = String(
        localized: "workspaces.calendar.keptForUserEvents",
        defaultValue: """
            In deze agenda staan ook afspraken van jou. De agenda blijft staan; de afspraken van Brievie zijn weg.
            """,
        bundle: .module
    )

    /// Under a calendar switch; `%@` is the calendar's name ("Brievie – Thuis").
    static let calendarFooterFormat = String(
        localized: "workspaces.calendar.footer",
        defaultValue: """
            Je taken met een deadline komen in een eigen agenda '%@'. De tekst van de taak en de afzender staan \
            erin. Die agenda kan via iCloud op je andere apparaten komen.
            """,
        bundle: .module
    )

    /// "Agenda 'Brievie – Thuis' ook verwijderen?"; `%@` is the calendar's name.
    static let calendarRemoveQuestionFormat = String(
        localized: "workspaces.calendar.remove.question",
        defaultValue: "Agenda '%@' ook verwijderen?",
        bundle: .module
    )

    /// Every string above by catalog key, for the parity test (not the plural one: see its own test).
    static let all: [String: String] = [
        "workspaces.kind.home": kindHome,
        "workspaces.kind.business": kindBusiness,
        "workspaces.kind.unknown": kindUnknown,
        "workspaces.role.admin": roleAdmin,
        "workspaces.role.member": roleMember,
        "workspaces.role.viewer": roleViewer,
        "workspaces.error.unreachable": unreachable,
        "workspaces.error.notVerified": notVerified,
        "error.generic": generic,
        "workspaces.unpair.message": unpairMessage,
        "workspaces.unpair.confirmRemovingCalendars": unpairRemovingCalendars,
        "workspaces.calendar.noAccess": calendarNoAccess,
        "workspaces.calendar.tasksNotSupported": calendarTasksNotSupported,
        "workspaces.calendar.footer": calendarFooterFormat,
        "workspaces.calendar.keptForUserEvents": calendarKeptForUserEvents,
        "workspaces.calendar.remove.question": calendarRemoveQuestionFormat
    ]
}
