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

    /// Under a calendar switch that is off (where the calendar goes is not decided yet); `%@` is the calendar's
    /// name ("Brievie – Thuis").
    static let calendarFooterFormat = String(
        localized: "workspaces.calendar.footer",
        defaultValue: """
            Je taken met een deadline komen in een eigen agenda '%@' in iCloud of op deze iPhone. \
            Een andere account gebruikt Brievie alleen als jij dat goedvindt.
            """,
        bundle: .module
    )

    /// Under a calendar switch whose calendar is in iCloud; `%@` is the calendar's name.
    static let calendarFooterICloudFormat = String(
        localized: "workspaces.calendar.footer.iCloud",
        defaultValue: """
            Je taken met een deadline staan in een eigen agenda '%@' in iCloud. \
            Die agenda staat ook op je andere apparaten met iCloud.
            """,
        bundle: .module
    )

    /// Under a calendar switch whose calendar is on this phone only; `%@` is the calendar's name.
    static let calendarFooterLocalFormat = String(
        localized: "workspaces.calendar.footer.local",
        defaultValue: "Je taken met een deadline staan in een eigen agenda '%@' op deze iPhone.",
        bundle: .module
    )

    /// Under a calendar switch whose calendar is in an account the user agreed to; `%1$@` is the calendar's name,
    /// `%2$@` the account's.
    static let calendarFooterOtherFormat = String(
        localized: "workspaces.calendar.footer.other",
        defaultValue: """
            Je taken met een deadline staan in een eigen agenda '%1$@' in de account %2$@. \
            Wie die account beheert, kan ze lezen.
            """,
        bundle: .module
    )

    /// The footer's last sentence while the description switch is off.
    static let calendarFooterNeutral = String(
        localized: "workspaces.calendar.footer.neutral",
        defaultValue: """
            In de agenda en bij meldingen op het toegangsscherm staat alleen de soort taak, \
            zoals 'Betalen (Brievie)'.
            """,
        bundle: .module
    )

    /// The footer's last sentence while the description switch is on.
    static let calendarFooterDetailed = String(
        localized: "workspaces.calendar.footer.detailed",
        defaultValue: "De omschrijving en de afzender staan in de agenda. Ook op het toegangsscherm zijn ze te lezen.",
        bundle: .module
    )

    /// Under "Toon de omschrijving in de agenda".
    static let calendarDetailsFooter = String(
        localized: "workspaces.calendar.details.footer",
        defaultValue: """
            Dan staan de omschrijving en de afzender in de agenda. Die tekst is dan te lezen op het toegangsscherm \
            en door andere apps die je agenda mogen lezen.
            """,
        bundle: .module
    )

    /// Asked before the calendar goes in an account that is not iCloud or this phone; `%@` is that account.
    static let calendarConsentFormat = String(
        localized: "workspaces.calendar.consent.question",
        defaultValue: "Brievie zet je taken in de agenda van %@. Wie die account beheert, kan ze lezen.",
        bundle: .module
    )

    /// The calendar's account is no longer on the phone: the switch went off.
    static let calendarSourceGone = String(
        localized: "workspaces.calendar.sourceGone",
        defaultValue: """
            De account van deze agenda staat niet meer op je telefoon. Daarom staat dit nu uit. \
            Zet het weer aan om een nieuwe agenda te maken.
            """,
        bundle: .module
    )

    /// The phone has no account a calendar can be made in.
    static let calendarNoCalendarAccount = String(
        localized: "workspaces.calendar.noCalendarAccount",
        defaultValue: "Er is op deze telefoon geen account waarin Brievie een agenda kan maken.",
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
        "workspaces.calendar.footer.iCloud": calendarFooterICloudFormat,
        "workspaces.calendar.footer.local": calendarFooterLocalFormat,
        "workspaces.calendar.footer.other": calendarFooterOtherFormat,
        "workspaces.calendar.consent.question": calendarConsentFormat,
        "workspaces.calendar.footer.neutral": calendarFooterNeutral,
        "workspaces.calendar.footer.detailed": calendarFooterDetailed,
        "workspaces.calendar.details.footer": calendarDetailsFooter,
        "workspaces.calendar.sourceGone": calendarSourceGone,
        "workspaces.calendar.noCalendarAccount": calendarNoCalendarAccount,
        "workspaces.calendar.keptForUserEvents": calendarKeptForUserEvents,
        "workspaces.calendar.remove.question": calendarRemoveQuestionFormat
    ].merging(reminders) { current, _ in current }
}
