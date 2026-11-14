import Foundation

/// Visible text of this target. The String Catalog (`Resources/Localizable.xcstrings`) is the source of
/// truth in the app; `defaultValue` repeats the Dutch text so that `swift test`, which does not compile
/// catalogs, sees the same words. `PairingModelTests` keeps the two equal.
enum PairingStrings {
    static let notBrievie = String(
        localized: "pairing.error.notBrievie",
        defaultValue: "Dit is geen Brievie-code. Open in de webinterface 'App koppelen' en scan de code daar.",
        bundle: .module
    )
    static let unsupportedVersion = String(
        localized: "pairing.error.unsupportedVersion",
        defaultValue: "Deze code komt van een nieuwere versie van Brievie. Werk de app bij en probeer het opnieuw.",
        bundle: .module
    )
    static let invalid = String(
        localized: "pairing.error.invalid",
        defaultValue: "Deze Brievie-code is niet geldig. Maak een nieuwe code.",
        bundle: .module
    )
    static let notVerified = String(
        localized: "pairing.error.notVerified",
        defaultValue: """
            We konden niet controleren of dit jouw Brievie-server is. \
            Maak een nieuwe code en probeer het opnieuw.
            """,
        bundle: .module
    )
    static let unreachable = String(
        localized: "pairing.error.unreachable",
        defaultValue: "We kunnen je Brievie-server niet bereiken. Zit je op hetzelfde netwerk?",
        bundle: .module
    )
    static let invalidCode = String(
        localized: "pairing.error.invalidCode",
        defaultValue: "Deze code is verlopen of al gebruikt. Maak een nieuwe code.",
        bundle: .module
    )
    static let connectionLost = String(
        localized: "pairing.error.connectionLost",
        defaultValue: "De verbinding viel weg tijdens het koppelen. Maak een nieuwe code en probeer het opnieuw.",
        bundle: .module
    )
    static let tooManyAttempts = String(
        localized: "pairing.error.tooManyAttempts",
        defaultValue: "Er zijn te veel pogingen gedaan. Wacht even en probeer het opnieuw.",
        bundle: .module
    )
    static let incompatible = String(
        localized: "pairing.error.incompatible",
        defaultValue: "Deze server en de app passen niet bij elkaar. Werk de app of de server bij.",
        bundle: .module
    )
    static let generic = String(
        localized: "error.generic",
        defaultValue: "Er ging iets mis. Probeer het opnieuw.",
        bundle: .module
    )

    /// Every string above by catalog key, for the parity test.
    static let all: [String: String] = [
        "pairing.error.notBrievie": notBrievie,
        "pairing.error.unsupportedVersion": unsupportedVersion,
        "pairing.error.invalid": invalid,
        "pairing.error.notVerified": notVerified,
        "pairing.error.unreachable": unreachable,
        "pairing.error.invalidCode": invalidCode,
        "pairing.error.connectionLost": connectionLost,
        "pairing.error.tooManyAttempts": tooManyAttempts,
        "pairing.error.incompatible": incompatible,
        "error.generic": generic
    ]
}
