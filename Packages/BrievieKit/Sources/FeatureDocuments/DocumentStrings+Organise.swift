import Foundation

extension DocumentStrings {
    // Review: on whose name a letter is, its labels, and where each proposal came from
    static let addressees = String(
        localized: "review.organise.addressees",
        defaultValue: "Op naam van",
        bundle: .module
    )
    static let labels = String(localized: "review.organise.labels", defaultValue: "Labels", bundle: .module)
    static let originAI = String(
        localized: "review.organise.origin.ai",
        defaultValue: "Voorstel van AI",
        bundle: .module
    )
    static let originNameMatch = String(
        localized: "review.organise.origin.nameMatch",
        defaultValue: "Herkend in de brief",
        bundle: .module
    )
    static let originRuleFormat = String(
        localized: "review.organise.origin.rule",
        defaultValue: "Regel: %@",
        bundle: .module
    )
    static let noAddressee = String(
        localized: "review.organise.noAddressee",
        defaultValue: "Nog op niemands naam.",
        bundle: .module
    )
    static let pickPersons = String(
        localized: "review.organise.pickPersons",
        defaultValue: "Kies personen",
        bundle: .module
    )
    static let pickLabels = String(
        localized: "review.organise.pickLabels",
        defaultValue: "Kies labels",
        bundle: .module
    )
    static let newPerson = String(
        localized: "review.organise.newPerson",
        defaultValue: "Nieuwe persoon",
        bundle: .module
    )
    static let newPersonName = String(
        localized: "review.organise.newPerson.name",
        defaultValue: "Naam",
        bundle: .module
    )
    static let newPersonAdd = String(
        localized: "review.organise.newPerson.add",
        defaultValue: "Toevoegen",
        bundle: .module
    )
    static let labelsInWeb = String(
        localized: "review.organise.labelsInWeb",
        defaultValue: "Nieuwe labels maak je in de webinterface.",
        bundle: .module
    )
    static let pickerDone = String(localized: "review.organise.done", defaultValue: "Klaar", bundle: .module)
    static let addFormat = String(localized: "review.organise.add", defaultValue: "%@ toevoegen", bundle: .module)
    static let chosenPersonFormat = String(
        localized: "review.organise.chosenPerson",
        defaultValue: "%@, op naam van. Tik om weg te halen",
        bundle: .module
    )
    static let chosenLabelFormat = String(
        localized: "review.organise.chosenLabel",
        defaultValue: "Label %@. Tik om weg te halen",
        bundle: .module
    )
    static let nameTaken = String(
        localized: "review.organise.nameTaken",
        defaultValue: "Er is al iemand met deze naam.",
        bundle: .module
    )
    static let organiseGone = String(
        localized: "review.organise.gone",
        defaultValue: "Een persoon of label bestaat niet meer. Controleer je keuze en bevestig opnieuw.",
        bundle: .module
    )

    // A confirmed letter: changes go to the server at once
    static let changeFailed = String(
        localized: "document.change.failed",
        defaultValue: "Dit lukte niet. Probeer het opnieuw.",
        bundle: .module
    )
    static let acceptSuggestion = String(
        localized: "document.suggestion.accept",
        defaultValue: "Toevoegen",
        bundle: .module
    )
    static let dismissSuggestion = String(
        localized: "document.suggestion.dismiss",
        defaultValue: "Negeren",
        bundle: .module
    )
    static let dismissFormat = String(
        localized: "document.suggestion.dismissNamed",
        defaultValue: "%@ negeren",
        bundle: .module
    )
    static let confirmedTasks = String(localized: "document.tasks", defaultValue: "Taken", bundle: .module)
    static let taskDone = String(localized: "document.task.done", defaultValue: "afgerond", bundle: .module)
    static let taskOpen = String(localized: "document.task.open", defaultValue: "open", bundle: .module)

    /// The strings of this part by catalog key, for the parity test (merged into `all`).
    static let organise: [String: String] = [
        "review.organise.addressees": addressees,
        "review.organise.labels": labels,
        "review.organise.origin.ai": originAI,
        "review.organise.origin.nameMatch": originNameMatch,
        "review.organise.origin.rule": originRuleFormat,
        "review.organise.noAddressee": noAddressee,
        "review.organise.pickPersons": pickPersons,
        "review.organise.pickLabels": pickLabels,
        "review.organise.newPerson": newPerson,
        "review.organise.newPerson.name": newPersonName,
        "review.organise.newPerson.add": newPersonAdd,
        "review.organise.labelsInWeb": labelsInWeb,
        "review.organise.done": pickerDone,
        "review.organise.add": addFormat,
        "review.organise.chosenPerson": chosenPersonFormat,
        "review.organise.chosenLabel": chosenLabelFormat,
        "review.organise.nameTaken": nameTaken,
        "review.organise.gone": organiseGone,
        "document.change.failed": changeFailed,
        "document.suggestion.accept": acceptSuggestion,
        "document.suggestion.dismiss": dismissSuggestion,
        "document.suggestion.dismissNamed": dismissFormat,
        "document.tasks": confirmedTasks,
        "document.task.done": taskDone,
        "document.task.open": taskOpen
    ]
}
