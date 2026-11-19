import Foundation

extension DocumentStrings {
    // The letter on the whole screen
    static let readerOpen = String(localized: "reader.open", defaultValue: "Brief lezen", bundle: .module)
    static let readerOpenHint = String(
        localized: "reader.open.hint",
        defaultValue: "Toont de brief op het hele scherm. Je kunt inzoomen of de tekst lezen.",
        bundle: .module
    )
    static let readerTitle = String(localized: "reader.title", defaultValue: "De brief", bundle: .module)
    static let readerMode = String(localized: "reader.mode", defaultValue: "Weergave", bundle: .module)
    static let readerModePage = String(localized: "reader.mode.page", defaultValue: "Pagina", bundle: .module)
    static let readerModeText = String(localized: "reader.mode.text", defaultValue: "Tekst", bundle: .module)
    static let readerPrevious = String(localized: "reader.previous", defaultValue: "Vorige pagina", bundle: .module)
    static let readerNext = String(localized: "reader.next", defaultValue: "Volgende pagina", bundle: .module)
    static let readerPageHint = String(
        localized: "reader.page.hint",
        defaultValue: "Kies bovenaan Tekst om de tekst van de brief te laten voorlezen.",
        bundle: .module
    )
    static let readerTextMissing = String(
        localized: "reader.text.missing",
        defaultValue: "Van deze pagina heeft de app geen tekst.",
        bundle: .module
    )

    /// The strings of this part by catalog key, for the parity test (merged into `all`).
    static let reader: [String: String] = [
        "reader.open": readerOpen,
        "reader.open.hint": readerOpenHint,
        "reader.title": readerTitle,
        "reader.mode": readerMode,
        "reader.mode.page": readerModePage,
        "reader.mode.text": readerModeText,
        "reader.previous": readerPrevious,
        "reader.next": readerNext,
        "reader.page.hint": readerPageHint,
        "reader.text.missing": readerTextMissing
    ]
}
