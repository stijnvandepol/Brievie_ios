import Foundation

/// Visible text of this target. The String Catalog (`Resources/Localizable.xcstrings`) is the source of
/// truth in the app; `defaultValue` repeats the Dutch text so that `swift test`, which does not compile
/// catalogs, sees the same words. `DocumentsModelTests.catalogAndCodeAgree` keeps the two equal.
/// Generated from one table; the parts below are extensions to keep each body short.
enum DocumentStrings {
    // Documents list, uploads and scanning
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
    static let addPost = String(localized: "documents.add", defaultValue: "Post toevoegen", bundle: .module)
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
}

extension DocumentStrings {
    // The review screen
    static let reviewTitle = String(localized: "review.title", defaultValue: "Controleren", bundle: .module)
    static let reviewLoading = String(localized: "review.loading", defaultValue: "Brief laden…", bundle: .module)
    static let pageFormat = String(localized: "review.pages", defaultValue: "Pagina %1$d van %2$d", bundle: .module)
    static let pageLoading = String(localized: "review.page.loading", defaultValue: "Pagina laden…", bundle: .module)
    static let sender = String(localized: "review.sender", defaultValue: "Afzender", bundle: .module)
    static let documentType = String(localized: "review.type", defaultValue: "Soort post", bundle: .module)
    static let typeNone = String(localized: "review.type.none", defaultValue: "Niet gekozen", bundle: .module)
    static let letterDate = String(localized: "review.letterDate", defaultValue: "Datum van de brief", bundle: .module)
    static let addDate = String(localized: "review.date.add", defaultValue: "Datum toevoegen", bundle: .module)
    static let removeDate = String(localized: "review.date.remove", defaultValue: "Datum weghalen", bundle: .module)
    static let summary = String(localized: "review.summary", defaultValue: "Uitleg", bundle: .module)
    static let summaryByAI = String(
        localized: "review.summary.ai",
        defaultValue: "Gemaakt door AI. Controleer of het klopt.",
        bundle: .module
    )
    static let whereIsThis = String(localized: "review.source", defaultValue: "Waar staat dit?", bundle: .module)
    static let sourceTitle = String(localized: "review.source.title", defaultValue: "Bron in de brief", bundle: .module)
    static let sourceMissing = String(
        localized: "review.source.missing",
        defaultValue: "We vonden deze zin niet terug in de tekst van de brief.",
        bundle: .module
    )
    static let checkCarefully = String(
        localized: "review.attention",
        defaultValue: "Controleer dit goed",
        bundle: .module
    )
    static let unverifiedFormat = String(
        localized: "review.unverified",
        defaultValue: "Voorstel van AI, niet teruggevonden in de brief: %@",
        bundle: .module
    )
    static let tasks = String(localized: "review.tasks", defaultValue: "Wat moet je doen", bundle: .module)
    static let taskType = String(localized: "review.task.type", defaultValue: "Soort taak", bundle: .module)
    static let taskDescription = String(
        localized: "review.task.description",
        defaultValue: "Omschrijving",
        bundle: .module
    )
    static let deadline = String(localized: "review.task.deadline", defaultValue: "Uiterste datum", bundle: .module)
    static let addTask = String(localized: "review.task.add", defaultValue: "Taak toevoegen", bundle: .module)
    static let removeTask = String(localized: "review.task.remove", defaultValue: "Taak verwijderen", bundle: .module)
    static let payInvoice = String(
        localized: "review.task.pay.default",
        defaultValue: "Betaal de rekening",
        bundle: .module
    )
    static let confirm = String(localized: "review.confirm", defaultValue: "Bevestigen", bundle: .module)
    static let saving = String(localized: "review.saving", defaultValue: "Opslaan…", bundle: .module)
    static let processingNote = String(
        localized: "review.processing",
        defaultValue: "De server verwerkt deze brief. Dit duurt meestal minder dan een minuut.",
        bundle: .module
    )
    static let processingFailedNote = String(
        localized: "review.failed",
        defaultValue: "Het verwerken is niet gelukt. Je kunt de gegevens zelf invullen of het opnieuw laten proberen.",
        bundle: .module
    )
    static let retryProcessing = String(
        localized: "review.retryProcessing",
        defaultValue: "Opnieuw verwerken",
        bundle: .module
    )
    static let readOnly = String(
        localized: "review.readOnly",
        defaultValue: "Je kunt in deze werkruimte alleen meekijken.",
        bundle: .module
    )
    static let sourceFormat = String(localized: "review.done.source", defaultValue: "Bron: “%@”", bundle: .module)
    static let manualSource = String(localized: "review.done.manual", defaultValue: "Zelf ingevuld", bundle: .module)
    static let noDeadline = String(localized: "review.done.noDeadline", defaultValue: "Geen datum", bundle: .module)
    static let noTasks = String(localized: "review.done.noTasks", defaultValue: "Geen taken", bundle: .module)
    static let taskNeedsDescription = String(
        localized: "review.error.taskNeedsDescription",
        defaultValue: "Geef elke taak een omschrijving.",
        bundle: .module
    )
    static let reviewRefused = String(
        localized: "review.error.refused",
        defaultValue: "De server kon dit niet opslaan. Controleer wat je hebt ingevuld.",
        bundle: .module
    )
    static let pageUnreadable = String(
        localized: "review.page.unreadable",
        defaultValue: "Deze pagina kan niet worden getoond.",
        bundle: .module
    )
}

extension DocumentStrings {
    // Document and task types
    static let docTypeInvoice = String(localized: "type.invoice", defaultValue: "Factuur", bundle: .module)
    static let docTypeAssessment = String(localized: "type.assessment", defaultValue: "Aanslag", bundle: .module)
    static let docTypeDecision = String(localized: "type.decision", defaultValue: "Beschikking", bundle: .module)
    static let docTypeBill = String(localized: "type.bill", defaultValue: "Rekening", bundle: .module)
    static let docTypeReminder = String(localized: "type.reminder", defaultValue: "Herinnering", bundle: .module)
    static let docTypeDemand = String(localized: "type.demand", defaultValue: "Aanmaning", bundle: .module)
    static let docTypePolicy = String(localized: "type.policy", defaultValue: "Polis", bundle: .module)
    static let docTypeAnnualStatement = String(
        localized: "type.annual_statement",
        defaultValue: "Jaaropgave",
        bundle: .module
    )
    static let docTypePayslip = String(localized: "type.payslip", defaultValue: "Loonstrook", bundle: .module)
    static let docTypeInspection = String(localized: "type.inspection", defaultValue: "Keuring", bundle: .module)
    static let docTypeContract = String(localized: "type.contract", defaultValue: "Contract", bundle: .module)
    static let docTypeReceipt = String(localized: "type.receipt", defaultValue: "Bonnetje", bundle: .module)
    static let docTypeInformation = String(localized: "type.information", defaultValue: "Informatie", bundle: .module)
    static let docTypeOther = String(localized: "type.other", defaultValue: "Overig", bundle: .module)
    static let taskTypePay = String(localized: "task.pay", defaultValue: "Betalen", bundle: .module)
    static let taskTypeRespond = String(localized: "task.respond", defaultValue: "Reageren", bundle: .module)
    static let taskTypeObject = String(localized: "task.object", defaultValue: "Bezwaar maken", bundle: .module)
    static let taskTypeApply = String(localized: "task.apply", defaultValue: "Aanvragen", bundle: .module)
    static let taskTypeInspection = String(localized: "task.inspection", defaultValue: "Keuring", bundle: .module)
    static let taskTypeCancel = String(localized: "task.cancel", defaultValue: "Opzeggen", bundle: .module)
    static let taskTypeRenew = String(localized: "task.renew", defaultValue: "Verlengen", bundle: .module)
    static let taskTypeFileTax = String(localized: "task.file_tax", defaultValue: "Aangifte doen", bundle: .module)
    static let taskTypeOther = String(localized: "task.other", defaultValue: "Overig", bundle: .module)
}

extension DocumentStrings {
    /// Every string above by catalog key, for the parity test.
    static let all: [String: String] = [
        "documents.new": newDocument,
        "documents.pages.one": pagesOne,
        "documents.pages.many": pagesManyFormat,
        "documents.section": section,
        "documents.loading": loading,
        "documents.empty": empty,
        "documents.scan": scan,
        "documents.add": addPost,
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
        "scan.error.noPages": noPages,
        "review.title": reviewTitle,
        "review.loading": reviewLoading,
        "review.pages": pageFormat,
        "review.page.loading": pageLoading,
        "review.sender": sender,
        "review.type": documentType,
        "review.type.none": typeNone,
        "review.letterDate": letterDate,
        "review.date.add": addDate,
        "review.date.remove": removeDate,
        "review.summary": summary,
        "review.summary.ai": summaryByAI,
        "review.source": whereIsThis,
        "review.source.title": sourceTitle,
        "review.source.missing": sourceMissing,
        "review.attention": checkCarefully,
        "review.unverified": unverifiedFormat,
        "review.tasks": tasks,
        "review.task.type": taskType,
        "review.task.description": taskDescription,
        "review.task.deadline": deadline,
        "review.task.add": addTask,
        "review.task.remove": removeTask,
        "review.task.pay.default": payInvoice,
        "review.confirm": confirm,
        "review.saving": saving,
        "review.processing": processingNote,
        "review.failed": processingFailedNote,
        "review.retryProcessing": retryProcessing,
        "review.readOnly": readOnly,
        "review.done.source": sourceFormat,
        "review.done.manual": manualSource,
        "review.done.noDeadline": noDeadline,
        "review.done.noTasks": noTasks,
        "review.error.taskNeedsDescription": taskNeedsDescription,
        "review.error.refused": reviewRefused,
        "type.invoice": docTypeInvoice,
        "type.assessment": docTypeAssessment,
        "type.decision": docTypeDecision,
        "type.bill": docTypeBill,
        "type.reminder": docTypeReminder,
        "type.demand": docTypeDemand,
        "type.policy": docTypePolicy,
        "type.annual_statement": docTypeAnnualStatement,
        "type.payslip": docTypePayslip,
        "type.inspection": docTypeInspection,
        "type.contract": docTypeContract,
        "type.receipt": docTypeReceipt,
        "type.information": docTypeInformation,
        "type.other": docTypeOther,
        "task.pay": taskTypePay,
        "task.respond": taskTypeRespond,
        "task.object": taskTypeObject,
        "task.apply": taskTypeApply,
        "task.inspection": taskTypeInspection,
        "task.cancel": taskTypeCancel,
        "task.renew": taskTypeRenew,
        "task.file_tax": taskTypeFileTax,
        "task.other": taskTypeOther,
        "review.page.unreadable": pageUnreadable
    ]
}
