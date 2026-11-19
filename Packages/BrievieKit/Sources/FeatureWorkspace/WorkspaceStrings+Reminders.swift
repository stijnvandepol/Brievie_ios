import Foundation

extension WorkspaceStrings {
    // "Herinneringen voor termijnen" in the settings

    static let remindersHeader = String(localized: "reminders.header", defaultValue: "Meldingen", bundle: .module)
    static let remindersToggle = String(
        localized: "reminders.toggle",
        defaultValue: "Herinneringen voor termijnen",
        bundle: .module
    )
    static let remindersWhenOnTheDay = String(
        localized: "reminders.footer.onTheDay",
        defaultValue: "Je krijgt om 9:00 een melding op de dag dat een termijn afloopt.",
        bundle: .module
    )
    static let remindersWhenDayBefore = String(
        localized: "reminders.footer.dayBefore",
        defaultValue: "Je krijgt om 9:00 een melding, een dag voordat een termijn afloopt en op de dag zelf.",
        bundle: .module
    )
    /// `%d` is the lead time in days, at least 2.
    static let remindersWhenDaysBeforeFormat = String(
        localized: "reminders.footer.daysBefore",
        defaultValue: "Je krijgt om 9:00 een melding, %d dagen voordat een termijn afloopt en op de dag zelf.",
        bundle: .module
    )
    /// What a reminder shows by default: the one sentence about the lock screen.
    static let remindersShowNothing = String(
        localized: "reminders.footer.neutral",
        defaultValue: "In de melding staat alleen dat er een termijn afloopt, niets uit de brief.",
        bundle: .module
    )
    static let remindersShowSender = String(
        localized: "reminders.footer.sender",
        defaultValue: "In de melding staat ook de afzender. Die is dan te lezen op het toegangsscherm.",
        bundle: .module
    )
    /// The limit of reminders made on the phone: they know what the app last read.
    static let remindersKnownOnly = String(
        localized: "reminders.footer.known",
        defaultValue: "Brievie herinnert je aan termijnen die de app kent. Open de app af en toe, dan blijft dat bij.",
        bundle: .module
    )
    static let remindersLead = String(localized: "reminders.lead", defaultValue: "Eerste melding", bundle: .module)
    static let remindersSenderToggle = String(
        localized: "reminders.sender.toggle",
        defaultValue: "Toon de afzender in herinneringen",
        bundle: .module
    )
    static let remindersSenderFooter = String(
        localized: "reminders.sender.footer",
        defaultValue: "Een bedrag of wat je moet doen staat nooit in de melding.",
        bundle: .module
    )
    static let remindersDenied = String(
        localized: "reminders.denied",
        defaultValue: "Brievie mag geen meldingen sturen. Zet meldingen voor Brievie aan in Instellingen.",
        bundle: .module
    )
    static let remindersOpenSettings = String(
        localized: "reminders.openSettings",
        defaultValue: "Open Instellingen",
        bundle: .module
    )

    static let reminderLeadOnTheDay = String(
        localized: "reminders.lead.0", defaultValue: "Op de dag zelf", bundle: .module
    )
    static let reminderLeadOneDay = String(localized: "reminders.lead.1", defaultValue: "1 dag ervoor", bundle: .module)
    static let reminderLeadTwoDays = String(
        localized: "reminders.lead.2", defaultValue: "2 dagen ervoor", bundle: .module
    )
    static let reminderLeadThreeDays = String(
        localized: "reminders.lead.3", defaultValue: "3 dagen ervoor", bundle: .module
    )
    static let reminderLeadWeek = String(localized: "reminders.lead.7", defaultValue: "1 week ervoor", bundle: .module)

    /// The name of a lead time in the picker; the planner offers 0, 1, 2, 3 and 7 days.
    static func reminderLeadOption(_ days: Int) -> String {
        switch days {
        case 0: reminderLeadOnTheDay
        case 1: reminderLeadOneDay
        case 2: reminderLeadTwoDays
        case 7: reminderLeadWeek
        default: reminderLeadThreeDays
        }
    }

    /// The strings of this part by catalog key, for the parity test (merged into `all`).
    static let reminders: [String: String] = [
        "reminders.header": remindersHeader,
        "reminders.toggle": remindersToggle,
        "reminders.footer.onTheDay": remindersWhenOnTheDay,
        "reminders.footer.dayBefore": remindersWhenDayBefore,
        "reminders.footer.daysBefore": remindersWhenDaysBeforeFormat,
        "reminders.footer.neutral": remindersShowNothing,
        "reminders.footer.sender": remindersShowSender,
        "reminders.footer.known": remindersKnownOnly,
        "reminders.lead": remindersLead,
        "reminders.sender.toggle": remindersSenderToggle,
        "reminders.sender.footer": remindersSenderFooter,
        "reminders.denied": remindersDenied,
        "reminders.openSettings": remindersOpenSettings,
        "reminders.lead.0": reminderLeadOnTheDay,
        "reminders.lead.1": reminderLeadOneDay,
        "reminders.lead.2": reminderLeadTwoDays,
        "reminders.lead.3": reminderLeadThreeDays,
        "reminders.lead.7": reminderLeadWeek
    ]
}
