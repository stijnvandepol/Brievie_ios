import Foundation

extension DocumentStrings {
    // The pages of a scan, checked before saving
    static let scanPreviewIntro = String(
        localized: "scan.preview.intro",
        defaultValue: "Kijk of elke pagina rechtop staat. Staat een pagina scheef of op zijn kop? Tik dan op Draai.",
        bundle: .module
    )
    static let scanTurn = String(localized: "scan.turn", defaultValue: "Draai", bundle: .module)
    /// VoiceOver label of the turn button; `%1$d` is the page number.
    static let scanTurnLabelFormat = String(
        localized: "scan.turn.label", defaultValue: "Draai pagina %1$d", bundle: .module
    )
    static let scanTurnHint = String(
        localized: "scan.turn.hint",
        defaultValue: "Draait de pagina een kwartslag met de klok mee en leest de tekst opnieuw.",
        bundle: .module
    )
    static let scanTurning = String(localized: "scan.turning", defaultValue: "Pagina draaien…", bundle: .module)
    static let scanTurnedAutomatically = String(
        localized: "scan.turned.auto",
        defaultValue: "De app heeft deze pagina rechtop gezet.",
        bundle: .module
    )
    static let scanSave = String(localized: "scan.save", defaultValue: "Bewaren", bundle: .module)
    static let scanSaving = String(localized: "scan.saving", defaultValue: "Scan bewaren…", bundle: .module)
    static let scanCancel = String(localized: "scan.cancel", defaultValue: "Annuleren", bundle: .module)
    static let scanDiscardTitle = String(
        localized: "scan.discard.title", defaultValue: "Deze scan weggooien?", bundle: .module
    )
    static let scanDiscard = String(localized: "scan.discard.confirm", defaultValue: "Weggooien", bundle: .module)

    /// The strings of this part by catalog key, for the parity test (merged into `all`).
    static let scanPreview: [String: String] = [
        "scan.preview.intro": scanPreviewIntro,
        "scan.turn": scanTurn,
        "scan.turn.label": scanTurnLabelFormat,
        "scan.turn.hint": scanTurnHint,
        "scan.turning": scanTurning,
        "scan.turned.auto": scanTurnedAutomatically,
        "scan.save": scanSave,
        "scan.saving": scanSaving,
        "scan.cancel": scanCancel,
        "scan.discard.title": scanDiscardTitle,
        "scan.discard.confirm": scanDiscard
    ]
}
