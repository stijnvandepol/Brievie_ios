import Foundation

extension DocumentStrings {
    // Deleting a letter to the trash, undo, and the Prullenbak screen
    static let trashButton = String(localized: "review.trash.button", defaultValue: "Verwijderen", bundle: .module)
    static let trashQuestion = String(
        localized: "review.trash.title", defaultValue: "Brief verwijderen?", bundle: .module
    )
    static let trashQuestionMessage = String(
        localized: "review.trash.message",
        defaultValue: """
        De brief gaat naar de prullenbak. Daar blijft hij 30 dagen. Zo lang kun je hem terugzetten. \
        Daarna wordt hij voorgoed gewist.
        """,
        bundle: .module
    )
    static let trashConfirm = String(
        localized: "review.trash.confirm", defaultValue: "Naar de prullenbak", bundle: .module
    )
    static let trashCancel = String(localized: "review.trash.cancel", defaultValue: "Annuleren", bundle: .module)
    /// A letter opened from a reminder or a stale list that is in the trash meanwhile.
    static let inTrash = String(
        localized: "review.inTrash", defaultValue: "Deze brief staat in de prullenbak.", bundle: .module
    )
    static let undoTrashed = String(
        localized: "documents.undo.trashed", defaultValue: "De brief staat in de prullenbak.", bundle: .module
    )
    static let undoAction = String(localized: "documents.undo.action", defaultValue: "Ongedaan maken", bundle: .module)
    static let undoClose = String(localized: "documents.undo.close", defaultValue: "Sluiten", bundle: .module)
    static let undoFailed = String(
        localized: "documents.undo.failed", defaultValue: "De brief kan niet meer worden teruggezet.", bundle: .module
    )
    static let forbidden = String(
        localized: "error.forbidden", defaultValue: "Je mag dit niet doen in deze werkruimte.", bundle: .module
    )
    /// The server is still reading the letter (409 `document_processing`), in the host's words.
    static let busy = String(
        localized: "error.busy", defaultValue: "Deze brief wordt nog gelezen. Probeer het zo opnieuw.", bundle: .module
    )
    static let uploadTrashed = String(
        localized: "documents.upload.trashed",
        defaultValue: "Deze brief staat al in de prullenbak. Zet hem daar terug als je hem weer wilt zien.",
        bundle: .module
    )
    static let trashTitle = String(localized: "trash.title", defaultValue: "Prullenbak", bundle: .module)
    static let trashIntroFormat = String(
        localized: "trash.intro",
        defaultValue: """
        Brieven in de prullenbak worden na %lld dagen voorgoed gewist. Tot die tijd kun je ze terugzetten.
        """,
        bundle: .module
    )
    static let trashWebOnly = String(
        localized: "trash.webOnly",
        defaultValue: "Definitief verwijderen en de prullenbak legen kan alleen in de webinterface.",
        bundle: .module
    )
    static let trashDeletedByFormat = String(
        localized: "trash.deleted.by", defaultValue: "Verwijderd op %1$@ door %2$@", bundle: .module
    )
    static let trashDeletedFormat = String(
        localized: "trash.deleted", defaultValue: "Verwijderd op %@", bundle: .module
    )
    static let trashErasedToday = String(
        localized: "trash.erasedToday", defaultValue: "Wordt vandaag gewist", bundle: .module
    )
    static let trashRestore = String(localized: "trash.restore", defaultValue: "Terugzetten", bundle: .module)
    static let trashRestoreLabelFormat = String(
        localized: "trash.restore.accessibility", defaultValue: "Terugzetten: %@", bundle: .module
    )
    static let trashRestored = String(
        localized: "trash.restored", defaultValue: "De brief is teruggezet.", bundle: .module
    )
    static let trashEmpty = String(localized: "trash.empty", defaultValue: "De prullenbak is leeg.", bundle: .module)
    static let trashCapFormat = String(
        localized: "trash.cap", defaultValue: "Alleen de nieuwste %lld worden getoond.", bundle: .module
    )

    /// "Nog 1 dag", "Nog 12 dagen": a plural variation in the catalog. `swift test` does not compile catalogs, so
    /// the default picks the form itself.
    static func trashDaysLeft(_ days: Int) -> String {
        String(
            localized: "trash.daysLeft",
            defaultValue: days == 1 ? "Nog \(days) dag" : "Nog \(days) dagen",
            bundle: .module
        )
    }

    /// The strings of this part by catalog key, for the parity test (merged into `all`).
    static let trash: [String: String] = [
        "review.trash.button": trashButton,
        "review.trash.title": trashQuestion,
        "review.trash.message": trashQuestionMessage,
        "review.trash.confirm": trashConfirm,
        "review.trash.cancel": trashCancel,
        "review.inTrash": inTrash,
        "documents.undo.trashed": undoTrashed,
        "documents.undo.action": undoAction,
        "documents.undo.close": undoClose,
        "documents.undo.failed": undoFailed,
        "error.forbidden": forbidden,
        "error.busy": busy,
        "documents.upload.trashed": uploadTrashed,
        "trash.title": trashTitle,
        "trash.intro": trashIntroFormat,
        "trash.webOnly": trashWebOnly,
        "trash.deleted.by": trashDeletedByFormat,
        "trash.deleted": trashDeletedFormat,
        "trash.erasedToday": trashErasedToday,
        "trash.restore": trashRestore,
        "trash.restore.accessibility": trashRestoreLabelFormat,
        "trash.restored": trashRestored,
        "trash.empty": trashEmpty,
        "trash.cap": trashCapFormat
    ]
}
