import Foundation

extension DocumentStrings {
    // The post list: "Te doen" as one list, what each row needs, the lines above and under the list

    /// A letter on the server whose sender is not known (read without one, or not read yet).
    static let unknownSender = String(
        localized: "documents.unknownSender",
        defaultValue: "Onbekende afzender",
        bundle: .module
    )
    static let statusNeedsName = String(
        localized: "documents.status.needsName",
        defaultValue: "Naam kiezen",
        bundle: .module
    )
    /// Under "Bezig…": the letter is being read, the person need not do anything.
    static let noteProcessing = String(
        localized: "documents.status.note.processing",
        defaultValue: "Je hoeft niets te doen.",
        bundle: .module
    )
    /// Under "Controleren" for a letter the server could not read.
    static let noteFailed = String(
        localized: "documents.status.note.failed",
        defaultValue: "Brievie kon deze brief niet goed lezen.",
        bundle: .module
    )
    /// The word for letters and scans on their way in the line above "Te doen" ("Bezig: 3").
    static let summaryUnderway = String(localized: "documents.summary.underway", defaultValue: "Bezig", bundle: .module)
    /// One part of the line above "Te doen": the row's word and how many.
    static let summaryCountFormat = String(
        localized: "documents.summary.count",
        defaultValue: "%1$@: %2$d",
        bundle: .module
    )
    /// One part of that line when the list holds only the newest: the word, how many there are, how many shown.
    static let summaryPartialFormat = String(
        localized: "documents.summary.partial",
        defaultValue: "%1$@: %2$d (de nieuwste %3$d)",
        bundle: .module
    )
    static let todoFooter = String(
        localized: "documents.inbox.footer",
        defaultValue: """
            Brieven waar jij nog iets mee moet doen. Al je brieven, ook de afgehandelde, staan bij Alle post.
            """,
        bundle: .module
    )
    static let allFooter = String(
        localized: "documents.all.footer",
        defaultValue: "Al je brieven, ook de afgehandelde. Wat nog op jou wacht, staat bij Te doen.",
        bundle: .module
    )
    /// Under "Je bent klaar. Er is niets te doen." for someone who may scan.
    static let todoEmptyHintScan = String(
        localized: "documents.inbox.empty.hintScan",
        defaultValue: "Een nieuwe brief scan je met de knop + bovenaan. Eerdere brieven vind je bij Alle post.",
        bundle: .module
    )
    /// The same for a viewer, who gets no scan button.
    static let todoEmptyHint = String(
        localized: "documents.inbox.empty.hint",
        defaultValue: "Eerdere brieven vind je bij Alle post.",
        bundle: .module
    )
    static let showAllPost = String(
        localized: "documents.inbox.showAll",
        defaultValue: "Bekijk Alle post",
        bundle: .module
    )

    /// Under the persons to choose from: what a person is (not a member who logs in).
    static let personsExplained = String(
        localized: "documents.persons.explained",
        defaultValue: "Op wiens naam brieven binnenkomen, ook iemand zonder account, zoals een kind.",
        bundle: .module
    )

    /// The strings of this part by catalog key, for the parity test (merged into `all`).
    static let list: [String: String] = [
        "documents.unknownSender": unknownSender,
        "documents.status.needsName": statusNeedsName,
        "documents.status.note.processing": noteProcessing,
        "documents.status.note.failed": noteFailed,
        "documents.summary.underway": summaryUnderway,
        "documents.summary.count": summaryCountFormat,
        "documents.summary.partial": summaryPartialFormat,
        "documents.inbox.footer": todoFooter,
        "documents.all.footer": allFooter,
        "documents.inbox.empty.hintScan": todoEmptyHintScan,
        "documents.inbox.empty.hint": todoEmptyHint,
        "documents.inbox.showAll": showAllPost,
        "documents.persons.explained": personsExplained
    ]
}
