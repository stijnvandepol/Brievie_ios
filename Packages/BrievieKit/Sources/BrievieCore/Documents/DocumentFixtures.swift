import Foundation

/// Example documents for tests and previews.
public enum DocumentFixtures {
    public static let letterText = """
        Belastingdienst
        Datum 3 november 2026
        U moet € 1.234,56 betalen vóór 1 december 2026.
        """

    public static func summary(
        id: UUID = UUID(), clientID: UUID = UUID(), status: DocumentStatus = .needsReview,
        sender: String = "", createdAt: Date = Date(timeIntervalSince1970: 1_794_650_400)
    ) -> DocumentSummary {
        DocumentSummary(
            id: id, clientID: clientID, status: status, pageCount: 1, createdAt: createdAt, sender: sender,
            documentType: "", letterDate: nil
        )
    }

    public static func proposal(
        _ field: String, _ value: String, quote: String = "", group: Int = 0, confidence: String = "0.9",
        needsAttention: Bool = false
    ) -> Proposal {
        Proposal(
            field: field, group: group, value: value, quote: quote,
            confidence: Decimal(string: confidence) ?? 0, needsAttention: needsAttention,
            provider: "api.mistral.ai", model: "mistral-small-latest"
        )
    }

    /// A letter from the tax office waiting for review, with one proposed payment.
    public static func detail(
        id: UUID = UUID(), status: DocumentStatus = .needsReview, proposals: [Proposal]? = nil,
        tasks: [ConfirmedTask] = [], failureCode: String = ""
    ) -> DocumentDetail {
        DocumentDetail(
            summary: summary(id: id, status: status),
            failureCode: failureCode,
            summaryText: "",
            summaryByAI: false,
            pageTexts: [letterText],
            proposals: proposals ?? [
                proposal("sender", "Belastingdienst", quote: "Belastingdienst", confidence: "0.97"),
                proposal("document_type", "assessment", confidence: "0.5"),
                proposal("letter_date", "2026-11-03", quote: "Datum 3 november 2026"),
                proposal("summary", "Je moet belasting betalen.", confidence: "0.5"),
                proposal("action_type", "pay", group: 1, confidence: "0.5"),
                proposal("action_description", "Betaal de aanslag", group: 1, confidence: "0.5"),
                proposal(
                    "action_deadline", "2026-12-01", quote: "vóór 1 december 2026", group: 1, confidence: "0.95"
                )
            ],
            tasks: tasks
        )
    }
}
