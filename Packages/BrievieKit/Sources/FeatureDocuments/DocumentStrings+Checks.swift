import Foundation

extension DocumentStrings {
    // Review: checks, conflicts, confirmations; scanning without camera access
    static let unchecked = String(
        localized: "review.unchecked",
        defaultValue: "Niet gecontroleerd",
        bundle: .module
    )
    static let letterDateToday = String(
        localized: "review.letterDate.today",
        defaultValue: "Dit is de datum van vandaag. Staat er een andere datum op de brief? Pas hem dan aan.",
        bundle: .module
    )
    static let confirmConflict = String(
        localized: "review.error.conflict",
        defaultValue: "Dat lukte nu niet. Wat je hebt ingevuld, staat er nog. Probeer het zo nog eens.",
        bundle: .module
    )
    static let discardEditsTitle = String(
        localized: "review.discard.title",
        defaultValue: "Wat je hebt ingevuld weggooien?",
        bundle: .module
    )
    static let discardEditsMessage = String(
        localized: "review.discard.message",
        defaultValue: "Opnieuw verwerken vervangt wat je zelf hebt ingevuld door nieuwe voorstellen.",
        bundle: .module
    )
    static let discardEdits = String(
        localized: "review.discard.confirm",
        defaultValue: "Weggooien en opnieuw verwerken",
        bundle: .module
    )
    static let keepEdits = String(localized: "review.discard.keep", defaultValue: "Niet weggooien", bundle: .module)
    static let taskLineFormat = String(localized: "review.done.taskLine", defaultValue: "%1$@ · %2$@", bundle: .module)
    static let cameraDenied = String(
        localized: "scan.camera.denied",
        defaultValue: "Brievie mag de camera niet gebruiken. Zet dit aan in Instellingen, of kies foto's van de brief.",
        bundle: .module
    )
    static let cameraRestricted = String(
        localized: "scan.camera.restricted",
        defaultValue: "De camera is op dit toestel uitgeschakeld. Kies foto's van de brief.",
        bundle: .module
    )
    static let openSettings = String(
        localized: "scan.camera.openSettings",
        defaultValue: "Open Instellingen",
        bundle: .module
    )

    // The post list: scopes, names, labels
    static let scopeInbox = String(localized: "documents.scope.inbox", defaultValue: "Inbox", bundle: .module)
    static let scopeAll = String(localized: "documents.scope.all", defaultValue: "Alle post", bundle: .module)
    static let inboxEmpty = String(
        localized: "documents.inbox.empty",
        defaultValue: "Je bent klaar. Er is niets te doen.",
        bundle: .module
    )
    static let personEmpty = String(
        localized: "documents.person.empty",
        defaultValue: "Er staat nog geen post op deze naam.",
        bundle: .module
    )
    static let addresseesFormat = String(
        localized: "documents.addressees",
        defaultValue: "Op naam van %@",
        bundle: .module
    )
    static let labelsFormat = String(localized: "documents.labels", defaultValue: "Labels: %@", bundle: .module)
    static let suggestion = String(localized: "documents.suggestion", defaultValue: "Voorstel", bundle: .module)

    /// `count` (at least 1) scans were removed from the queue because their record could not be read. The
    /// catalog has the singular and plural; the default here is the plural (`swift test` reads no catalogs).
    static func unreadableRemoved(_ count: Int) -> String {
        String(
            localized: "documents.upload.unreadableRemoved",
            defaultValue: "\(count) scans konden niet worden gelezen en zijn verwijderd.",
            bundle: .module
        )
    }
}
