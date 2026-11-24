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

    static let navigation: [String: String] = [
        "documents.scope.myPost": scopeMyPost,
        "documents.forWhom": forWhom,
        "documents.forWhom.everyone": forEveryone,
        "documents.myPost.empty": myPostEmpty,
        "tabs.tasks": tabTasks,
        "tabs.more": tabMore,
        "tabs.labels": labelsTitle,
        "tabs.settings": settingsTitle
    ]
}
