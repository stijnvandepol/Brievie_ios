import Foundation

/// The document and task types of the API with their Dutch names, in the order the pickers show them.
enum DocumentTypes {
    static let documentTypes: [(code: String, label: String)] = [
        ("invoice", DocumentStrings.docTypeInvoice),
        ("bill", DocumentStrings.docTypeBill),
        ("reminder", DocumentStrings.docTypeReminder),
        ("demand", DocumentStrings.docTypeDemand),
        ("assessment", DocumentStrings.docTypeAssessment),
        ("decision", DocumentStrings.docTypeDecision),
        ("policy", DocumentStrings.docTypePolicy),
        ("annual_statement", DocumentStrings.docTypeAnnualStatement),
        ("payslip", DocumentStrings.docTypePayslip),
        ("inspection", DocumentStrings.docTypeInspection),
        ("contract", DocumentStrings.docTypeContract),
        ("receipt", DocumentStrings.docTypeReceipt),
        ("information", DocumentStrings.docTypeInformation),
        ("other", DocumentStrings.docTypeOther)
    ]

    static let taskTypes: [(code: String, label: String)] = [
        ("pay", DocumentStrings.taskTypePay),
        ("respond", DocumentStrings.taskTypeRespond),
        ("object", DocumentStrings.taskTypeObject),
        ("apply", DocumentStrings.taskTypeApply),
        ("inspection", DocumentStrings.taskTypeInspection),
        ("cancel", DocumentStrings.taskTypeCancel),
        ("renew", DocumentStrings.taskTypeRenew),
        ("file_tax", DocumentStrings.taskTypeFileTax),
        ("other", DocumentStrings.taskTypeOther)
    ]

    /// A code this app knows, or `other`: API v1 may add types later.
    static func knownDocumentType(_ code: String) -> String {
        documentTypes.contains { $0.code == code } ? code : "other"
    }

    static func knownTaskType(_ code: String) -> String {
        taskTypes.contains { $0.code == code } ? code : "other"
    }

    static func documentTypeLabel(_ code: String) -> String {
        documentTypes.first { $0.code == code }?.label ?? DocumentStrings.docTypeOther
    }

    static func taskTypeLabel(_ code: String) -> String {
        taskTypes.first { $0.code == code }?.label ?? DocumentStrings.taskTypeOther
    }
}
