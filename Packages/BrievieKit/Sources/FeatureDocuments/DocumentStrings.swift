import Foundation

/// Visible text of this target. The String Catalog (`Resources/Localizable.xcstrings`) is the source of
/// truth in the app; `defaultValue` repeats the Dutch text so that `swift test`, which does not compile
/// catalogs, sees the same words. `DocumentsModelTests.catalogAndCodeAgree` keeps the two equal.
enum DocumentStrings {
    static let newDocument = String(localized: "documents.new", defaultValue: "Nieuw document", bundle: .module)
    static let pagesOne = String(localized: "documents.pages.one", defaultValue: "1 pagina", bundle: .module)
    static let pagesManyFormat = String(localized: "documents.pages.many", defaultValue: "%d pagina's", bundle: .module)
    static let section = String(localized: "documents.section", defaultValue: "Post", bundle: .module)
    static let loading = String(localized: "documents.loading", defaultValue: "Post laden…", bundle: .module)
    static let empty = String(
        localized: "documents.empty",
        defaultValue: "Nog geen post. Scan je eerste brief.",
        bundle: .module
    )
    static let scan = String(localized: "documents.scan", defaultValue: "Scan een brief", bundle: .module)
    static let importPhotos = String(localized: "documents.import", defaultValue: "Kies foto's", bundle: .module)
    static let retry = String(localized: "documents.retry", defaultValue: "Opnieuw proberen", bundle: .module)
    static let delete = String(localized: "documents.delete", defaultValue: "Verwijderen", bundle: .module)
    static let statusWaiting = String(
        localized: "documents.status.waiting",
        defaultValue: "Wacht op verbinding",
        bundle: .module
    )
    static let statusUploading = String(
        localized: "documents.status.uploading",
        defaultValue: "Uploaden…",
        bundle: .module
    )
    static let statusUploadFailed = String(
        localized: "documents.status.uploadFailed",
        defaultValue: "Upload mislukt",
        bundle: .module
    )
    static let statusProcessing = String(
        localized: "documents.status.processing",
        defaultValue: "Wordt verwerkt",
        bundle: .module
    )
    static let statusNeedsReview = String(
        localized: "documents.status.needsReview",
        defaultValue: "Controleer dit",
        bundle: .module
    )
    static let statusDone = String(localized: "documents.status.done", defaultValue: "Klaar", bundle: .module)
    static let statusFailed = String(
        localized: "documents.status.failed",
        defaultValue: "Verwerken mislukt",
        bundle: .module
    )
    static let unreachable = String(
        localized: "documents.error.unreachable",
        defaultValue: "We kunnen je Brievie-server niet bereiken. Zit je op hetzelfde netwerk?",
        bundle: .module
    )
    static let notVerified = String(
        localized: "documents.error.notVerified",
        defaultValue: """
            We konden niet controleren of dit jouw Brievie-server is. Koppel de app opnieuw als dit blijft \
            gebeuren.
            """,
        bundle: .module
    )
    static let notFound = String(
        localized: "documents.error.notFound",
        defaultValue: "Dit document bestaat niet meer.",
        bundle: .module
    )
    static let generic = String(
        localized: "error.generic",
        defaultValue: "Er ging iets mis. Probeer het opnieuw.",
        bundle: .module
    )
    static let uploadFailed = String(
        localized: "documents.upload.failed",
        defaultValue: "Uploaden is niet gelukt.",
        bundle: .module
    )
    static let workspaceGone = String(
        localized: "documents.upload.workspaceGone",
        defaultValue: "Deze werkruimte bestaat niet meer op de server.",
        bundle: .module
    )
    static let tooLarge = String(
        localized: "documents.upload.tooLarge",
        defaultValue: "Deze scan is te groot. Scan minder pagina's tegelijk.",
        bundle: .module
    )
    static let scanTitle = String(localized: "scan.title", defaultValue: "Scan bewaren", bundle: .module)
    static let recognisingFormat = String(
        localized: "scan.recognising",
        defaultValue: "Tekst herkennen: pagina %1$d van %2$d",
        bundle: .module
    )
    static let scanClose = String(localized: "scan.close", defaultValue: "Sluiten", bundle: .module)
    static let tooManyPages = String(
        localized: "scan.error.tooManyPages",
        defaultValue: "Je kunt maximaal 30 pagina's in één keer scannen.",
        bundle: .module
    )
    static let diskFull = String(
        localized: "scan.error.diskFull",
        defaultValue: "Er is niet genoeg ruimte op je telefoon om de scan te bewaren.",
        bundle: .module
    )
    static let unreadablePage = String(
        localized: "scan.error.unreadable",
        defaultValue: "Een pagina kon niet worden gelezen. Scan de brief opnieuw.",
        bundle: .module
    )
    static let scanFailed = String(
        localized: "scan.error.failed",
        defaultValue: "De scan kon niet worden bewaard. Probeer het opnieuw.",
        bundle: .module
    )
    static let noPages = String(
        localized: "scan.error.noPages",
        defaultValue: "Er zijn geen pagina's gescand.",
        bundle: .module
    )

    /// Every string above by catalog key, for the parity test.
    static let all: [String: String] = [
        "documents.new": newDocument,
        "documents.pages.one": pagesOne,
        "documents.pages.many": pagesManyFormat,
        "documents.section": section,
        "documents.loading": loading,
        "documents.empty": empty,
        "documents.scan": scan,
        "documents.import": importPhotos,
        "documents.retry": retry,
        "documents.delete": delete,
        "documents.status.waiting": statusWaiting,
        "documents.status.uploading": statusUploading,
        "documents.status.uploadFailed": statusUploadFailed,
        "documents.status.processing": statusProcessing,
        "documents.status.needsReview": statusNeedsReview,
        "documents.status.done": statusDone,
        "documents.status.failed": statusFailed,
        "documents.error.unreachable": unreachable,
        "documents.error.notVerified": notVerified,
        "documents.error.notFound": notFound,
        "error.generic": generic,
        "documents.upload.failed": uploadFailed,
        "documents.upload.workspaceGone": workspaceGone,
        "documents.upload.tooLarge": tooLarge,
        "scan.title": scanTitle,
        "scan.recognising": recognisingFormat,
        "scan.close": scanClose,
        "scan.error.tooManyPages": tooManyPages,
        "scan.error.diskFull": diskFull,
        "scan.error.unreadable": unreadablePage,
        "scan.error.failed": scanFailed,
        "scan.error.noPages": noPages
    ]
}
