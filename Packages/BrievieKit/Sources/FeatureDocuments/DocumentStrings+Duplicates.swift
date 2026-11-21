import Foundation

extension DocumentStrings {
    // "Dubbel?" in Te doen, the compare screen, merge and dismiss
    static let duplicateChip = String(localized: "duplicates.chip", defaultValue: "Dubbel?", bundle: .module)
    static let duplicateGroupNote = String(
        localized: "duplicates.group.note",
        defaultValue: "Deze brieven lijken twee keer gescand. Kijk of het dezelfde brief is.",
        bundle: .module
    )
    static let duplicateSimilarityFormat = String(
        localized: "duplicates.similarity", defaultValue: "Lijkt op elkaar voor %lld%%", bundle: .module
    )
    static let duplicateTitle = String(localized: "duplicates.title", defaultValue: "Mogelijk dubbel", bundle: .module)
    static let duplicateDescription = String(
        localized: "duplicates.description",
        defaultValue: """
        Deze twee brieven lijken op elkaar. Is het dezelfde brief, twee keer gescand? Kijk wat hetzelfde is en \
        wat verschilt.
        """,
        bundle: .module
    )
    static let duplicateLetterFormat = String(
        localized: "duplicates.letter", defaultValue: "Brief %lld", bundle: .module
    )
    static let duplicateScannedFormat = String(
        localized: "duplicates.scanned", defaultValue: "Gescand op %@", bundle: .module
    )
    static let duplicateFirstPageFormat = String(
        localized: "duplicates.firstPage", defaultValue: "Eerste pagina van brief %lld", bundle: .module
    )
    static let duplicateSender = String(localized: "duplicates.field.sender", defaultValue: "Afzender", bundle: .module)
    static let duplicateKind = String(localized: "duplicates.field.kind", defaultValue: "Soort", bundle: .module)
    static let duplicateDate = String(localized: "duplicates.field.date", defaultValue: "Datum", bundle: .module)
    static let duplicateAmount = String(localized: "duplicates.field.amount", defaultValue: "Bedrag", bundle: .module)
    static let duplicateInvoiceNumber = String(
        localized: "duplicates.field.invoiceNumber", defaultValue: "Factuurnummer", bundle: .module
    )
    static let duplicateReference = String(
        localized: "duplicates.field.reference", defaultValue: "Kenmerk", bundle: .module
    )
    static let duplicatePages = String(localized: "duplicates.field.pages", defaultValue: "Pagina's", bundle: .module)
    static let duplicateLabels = String(localized: "duplicates.field.labels", defaultValue: "Labels", bundle: .module)
    static let duplicateAddressees = String(
        localized: "duplicates.field.addressees", defaultValue: "Op naam van", bundle: .module
    )
    static let duplicateTasks = String(localized: "duplicates.field.tasks", defaultValue: "Taken", bundle: .module)
    static let duplicateNone = String(localized: "duplicates.none", defaultValue: "Geen", bundle: .module)
    static let duplicateTaskDoneFormat = String(
        localized: "duplicates.taskDone", defaultValue: "%@, afgerond", bundle: .module
    )
    static let duplicateDiffers = String(localized: "duplicates.differs", defaultValue: "Verschilt", bundle: .module)
    static let duplicateMayDiffer = String(
        localized: "duplicates.mayDiffer", defaultValue: "Verschilt misschien (slecht leesbaar)", bundle: .module
    )
    static let duplicateKeepQuestion = String(
        localized: "duplicates.keep.question", defaultValue: "Welke brief houd je?", bundle: .module
    )
    static let duplicateKeepLabelFormat = String(
        localized: "duplicates.keep.accessibility", defaultValue: "Deze brief houden: brief %lld", bundle: .module
    )
    static let duplicateSameLetter = String(
        localized: "duplicates.same", defaultValue: "Het is dezelfde brief", bundle: .module
    )
    static let duplicateTwoLetters = String(
        localized: "duplicates.two", defaultValue: "Het zijn twee brieven", bundle: .module
    )
    static let duplicateVisibilityDiffers = String(
        localized: "duplicates.visibilityDiffers",
        defaultValue: """
        Deze twee brieven zijn niet voor dezelfde mensen zichtbaar. Daarom kun je ze niet samenvoegen. \
        Kies 'Het zijn twee brieven', of laat ze eerst voor dezelfde mensen zichtbaar zijn.
        """,
        bundle: .module
    )
    static let duplicateMergeTitle = String(
        localized: "duplicates.merge.title", defaultValue: "Samenvoegen?", bundle: .module
    )
    static let duplicateMergeMessage = String(
        localized: "duplicates.merge.message",
        defaultValue: """
        De brief die je houdt, krijgt de labels en personen van allebei. De andere brief gaat naar de \
        prullenbak. Daar kun je hem 30 dagen terugzetten.
        """,
        bundle: .module
    )
    static let duplicateCompleteTask = String(
        localized: "duplicates.merge.completeTask", defaultValue: "Taak ook afronden", bundle: .module
    )
    static let duplicateTwinNoteFormat = String(
        localized: "duplicates.merge.twinNote", defaultValue: "Op de andere scan is '%@' al afgerond.", bundle: .module
    )
    static let duplicateMergeConfirm = String(
        localized: "duplicates.merge.confirm", defaultValue: "Samenvoegen", bundle: .module
    )
    static let duplicateMergeCancel = String(
        localized: "duplicates.merge.cancel", defaultValue: "Annuleren", bundle: .module
    )
    static let duplicateDismissed = String(
        localized: "duplicates.dismissed",
        defaultValue: "Goed. We vragen het niet meer voor deze twee brieven.",
        bundle: .module
    )
    static let duplicateGone = String(
        localized: "duplicates.gone", defaultValue: "Deze dubbele brieven zijn er niet (meer).", bundle: .module
    )
    static let duplicateDecided = String(
        localized: "duplicates.decided", defaultValue: "Over deze twee brieven is al gekozen.", bundle: .module
    )

    /// The strings of this part by catalog key, for the parity test (merged into `all`).
    static let duplicates: [String: String] = [
        "duplicates.chip": duplicateChip,
        "duplicates.group.note": duplicateGroupNote,
        "duplicates.similarity": duplicateSimilarityFormat,
        "duplicates.title": duplicateTitle,
        "duplicates.description": duplicateDescription,
        "duplicates.letter": duplicateLetterFormat,
        "duplicates.scanned": duplicateScannedFormat,
        "duplicates.firstPage": duplicateFirstPageFormat,
        "duplicates.field.sender": duplicateSender,
        "duplicates.field.kind": duplicateKind,
        "duplicates.field.date": duplicateDate,
        "duplicates.field.amount": duplicateAmount,
        "duplicates.field.invoiceNumber": duplicateInvoiceNumber,
        "duplicates.field.reference": duplicateReference,
        "duplicates.field.pages": duplicatePages,
        "duplicates.field.labels": duplicateLabels,
        "duplicates.field.addressees": duplicateAddressees,
        "duplicates.field.tasks": duplicateTasks,
        "duplicates.none": duplicateNone,
        "duplicates.taskDone": duplicateTaskDoneFormat,
        "duplicates.differs": duplicateDiffers,
        "duplicates.mayDiffer": duplicateMayDiffer,
        "duplicates.keep.question": duplicateKeepQuestion,
        "duplicates.keep.accessibility": duplicateKeepLabelFormat,
        "duplicates.same": duplicateSameLetter,
        "duplicates.two": duplicateTwoLetters,
        "duplicates.visibilityDiffers": duplicateVisibilityDiffers,
        "duplicates.merge.title": duplicateMergeTitle,
        "duplicates.merge.message": duplicateMergeMessage,
        "duplicates.merge.completeTask": duplicateCompleteTask,
        "duplicates.merge.twinNote": duplicateTwinNoteFormat,
        "duplicates.merge.confirm": duplicateMergeConfirm,
        "duplicates.merge.cancel": duplicateMergeCancel,
        "duplicates.dismissed": duplicateDismissed,
        "duplicates.gone": duplicateGone,
        "duplicates.decided": duplicateDecided
    ]
}
