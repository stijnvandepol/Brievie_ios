import Foundation

// The tabs, "Mijn post", "Ongelezen" and "Blijft liggen" (navigation design, host PR #44).
extension DocumentStrings {
    static let scopeMyPost = String(localized: "documents.scope.myPost", defaultValue: "Mijn post", bundle: .module)
    /// The "Voor wie" filter of "Alle post": its label, and its first choice (every letter).
    static let forWhom = String(localized: "documents.forWhom", defaultValue: "Voor wie", bundle: .module)
    static let forEveryone = String(
        localized: "documents.forWhom.everyone", defaultValue: "Iedereen", bundle: .module
    )
    static let tabTasks = String(localized: "tabs.tasks", defaultValue: "Taken", bundle: .module)
    static let tabMore = String(localized: "tabs.more", defaultValue: "Meer", bundle: .module)
    static let labelsTitle = String(localized: "tabs.labels", defaultValue: "Labels", bundle: .module)
    static let settingsTitle = String(localized: "tabs.settings", defaultValue: "Instellingen", bundle: .module)
    static let myPostEmpty = String(
        localized: "documents.myPost.empty", defaultValue: "Er is nog geen post op jouw naam.", bundle: .module
    )
    static let myPostAllRead = String(
        localized: "documents.myPost.allRead", defaultValue: "Je hebt alles gelezen.", bundle: .module
    )
    static let myPostNoPerson = String(
        localized: "documents.myPost.noPerson",
        defaultValue: """
            Je account is nog niet aan een persoon gekoppeld. Vraag een beheerder om dat te doen. \
            Daarna staat hier de post op jouw naam.
            """,
        bundle: .module
    )

    // Ongelezen
    static let unread = String(localized: "documents.unread", defaultValue: "Ongelezen", bundle: .module)
    static let unreadOnly = String(
        localized: "documents.unreadOnly", defaultValue: "Alleen ongelezen", bundle: .module
    )
    static let swipeRead = String(localized: "documents.swipe.read", defaultValue: "Gelezen", bundle: .module)
    static let swipeUnread = String(localized: "documents.swipe.unread", defaultValue: "Ongelezen", bundle: .module)
    static let markRead = String(
        localized: "documents.markRead", defaultValue: "Markeer als gelezen", bundle: .module
    )
    static let markUnread = String(
        localized: "documents.markUnread", defaultValue: "Markeer als ongelezen", bundle: .module
    )

    // Round quick actions
    static let actionScan = String(localized: "actions.scan", defaultValue: "Scannen", bundle: .module)
    static let actionSearch = String(localized: "actions.search", defaultValue: "Zoeken", bundle: .module)
    static let actionAllRead = String(localized: "actions.allRead", defaultValue: "Alles gelezen", bundle: .module)
    static let actionChooseName = String(
        localized: "actions.chooseName", defaultValue: "Naam kiezen", bundle: .module
    )

    // Count cards
    static let cardUnread = String(localized: "cards.unread", defaultValue: "ongelezen", bundle: .module)
    static let cardTasks = String(localized: "cards.tasks", defaultValue: "taken", bundle: .module)
    static let cardLingering = String(
        localized: "cards.lingering", defaultValue: "blijven liggen", bundle: .module
    )

    static func cardLateDetail(_ late: Int) -> String {
        String(localized: "cards.tasks.late", defaultValue: "\(late) te laat", bundle: .module)
    }

    /// What VoiceOver says for a count card: the place and the number in words, never a bare number.
    static func cardUnreadLabel(_ count: Int) -> String {
        String(localized: "cards.unread.label", defaultValue: "Mijn post: \(count) ongelezen", bundle: .module)
    }

    static func cardTasksLabel(_ count: Int, late: Int) -> String {
        late > 0
            ? String(
                localized: "cards.tasks.label.late", defaultValue: "Mijn taken: \(count) open, \(late) te laat",
                bundle: .module
            )
            : String(localized: "cards.tasks.label", defaultValue: "Mijn taken: \(count) open", bundle: .module)
    }

    static func cardLingeringLabel(_ count: Int) -> String {
        String(localized: "cards.lingering.label", defaultValue: "Blijft liggen: \(count)", bundle: .module)
    }

    // Blijft liggen
    static let lingeringTitle = String(localized: "lingering.title", defaultValue: "Blijft liggen", bundle: .module)
    static let lingeringTooLong = String(
        localized: "lingering.tooLong", defaultValue: "In de Inbox te lang", bundle: .module
    )
    static let lingeringNotOpened = String(
        localized: "lingering.notOpened", defaultValue: "Nog niet geopend", bundle: .module
    )
    static let lingeringEmpty = String(
        localized: "lingering.empty", defaultValue: "Er blijft niets liggen.", bundle: .module
    )

    /// "Ligt er 4 dagen"; the catalog has the singular and the plural.
    static func lingeringInboxDays(_ days: Int) -> String {
        days == 1
            ? String(localized: "lingering.days.inbox", defaultValue: "Ligt er \(days) dag", bundle: .module)
            : String(localized: "lingering.days.inbox", defaultValue: "Ligt er \(days) dagen", bundle: .module)
    }

    /// "5 dagen niet geopend".
    static func lingeringUnopenedDays(_ days: Int) -> String {
        days == 1
            ? String(localized: "lingering.days.unopened", defaultValue: "\(days) dag niet geopend", bundle: .module)
            : String(localized: "lingering.days.unopened", defaultValue: "\(days) dagen niet geopend", bundle: .module)
    }

    // Labels
    static let labelsEmpty = String(
        localized: "labels.empty", defaultValue: "Deze werkruimte heeft nog geen labels.", bundle: .module
    )
    static let labelsFooter = String(
        localized: "labels.footer", defaultValue: "Labels maak en wijzig je op de website.", bundle: .module
    )
    static let labelEmpty = String(
        localized: "labels.letters.empty", defaultValue: "Er is nog geen post met dit label.", bundle: .module
    )

    static let navigation: [String: String] = [
        "documents.scope.myPost": scopeMyPost,
        "documents.forWhom": forWhom,
        "documents.forWhom.everyone": forEveryone,
        "documents.myPost.empty": myPostEmpty,
        "tabs.tasks": tabTasks,
        "tabs.more": tabMore,
        "tabs.labels": labelsTitle,
        "tabs.settings": settingsTitle,
        "documents.myPost.allRead": myPostAllRead,
        "documents.myPost.noPerson": myPostNoPerson,
        "documents.unread": unread,
        "documents.unreadOnly": unreadOnly,
        "documents.swipe.read": swipeRead,
        "documents.swipe.unread": swipeUnread,
        "documents.markRead": markRead,
        "documents.markUnread": markUnread,
        "actions.scan": actionScan,
        "actions.search": actionSearch,
        "actions.allRead": actionAllRead,
        "actions.chooseName": actionChooseName,
        "cards.unread": cardUnread,
        "cards.tasks": cardTasks,
        "cards.lingering": cardLingering,
        "lingering.title": lingeringTitle,
        "lingering.tooLong": lingeringTooLong,
        "lingering.notOpened": lingeringNotOpened,
        "lingering.empty": lingeringEmpty,
        "labels.empty": labelsEmpty,
        "labels.footer": labelsFooter,
        "labels.letters.empty": labelEmpty
    ]
}
