import Foundation

extension DocumentStrings {
    // A task's termijn and removing a task in the review
    static let deadlinePickHint = String(
        localized: "review.deadline.pick.hint",
        defaultValue: "Tik op een dag. Tot dan blijft de termijn leeg.",
        bundle: .module
    )
    static let deadlinePickToday = String(
        localized: "review.deadline.pick.today", defaultValue: "Vandaag", bundle: .module
    )
    static let deadlinePickCancel = String(
        localized: "review.deadline.pick.cancel", defaultValue: "Annuleren", bundle: .module
    )
    static let removeTaskTitle = String(
        localized: "review.task.remove.title", defaultValue: "Deze taak verwijderen?", bundle: .module
    )
    static let removeTaskMessage = String(
        localized: "review.task.remove.message",
        defaultValue: "De taak en de termijn gaan weg uit deze brief.",
        bundle: .module
    )
    static let removeTaskConfirm = String(
        localized: "review.task.remove.confirm", defaultValue: "Verwijderen", bundle: .module
    )
    static let removeTaskKeep = String(
        localized: "review.task.remove.keep", defaultValue: "Laten staan", bundle: .module
    )
    static let openProposalsOneFormat = String(
        localized: "review.proposals.open.one",
        defaultValue: "Er staat nog 1 voorstel open: %@. Neem je het niet over, dan vervalt het als je bevestigt.",
        bundle: .module
    )
    static let openProposalsManyFormat = String(
        localized: "review.proposals.open.many",
        defaultValue: """
        Er staan nog %1$d voorstellen open: %2$@. \
        Neem je ze niet over, dan vervallen ze als je bevestigt.
        """,
        bundle: .module
    )

    /// The strings of this part by catalog key, for the parity test (merged into `all`).
    static let taskEditing: [String: String] = [
        "review.deadline.pick.hint": deadlinePickHint,
        "review.deadline.pick.today": deadlinePickToday,
        "review.deadline.pick.cancel": deadlinePickCancel,
        "review.task.remove.title": removeTaskTitle,
        "review.task.remove.message": removeTaskMessage,
        "review.task.remove.confirm": removeTaskConfirm,
        "review.task.remove.keep": removeTaskKeep,
        "review.proposals.open.one": openProposalsOneFormat,
        "review.proposals.open.many": openProposalsManyFormat
    ]
}
