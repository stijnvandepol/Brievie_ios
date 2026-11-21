import Foundation

/// Example documents for tests and previews.
public enum DocumentFixtures {
    public static let letterText = """
        Belastingdienst
        Datum 3 november 2026
        U moet € 1.234,56 betalen vóór 1 december 2026.
        """

    public static let persons = [
        Person(
            id: UUID(uuidString: "3F0C8A52-6D0E-4C8E-9A51-1E2B3C4D5E6F") ?? UUID(), displayName: "Stijn",
            nameVariants: ["J. de Wilde"], isArchived: false
        ),
        Person(
            id: UUID(uuidString: "7E6D5C4B-3A29-4180-9F7E-6D5C4B3A2918") ?? UUID(), displayName: "Anne",
            nameVariants: [], isArchived: false
        )
    ]

    public static let labels = [
        DocumentLabel(id: UUID(uuidString: "9A8B7C6D-5E4F-4A3B-8C2D-1E0F9A8B7C6D") ?? UUID(), name: "Zorg",
                      colorKey: "green"),
        DocumentLabel(id: UUID(uuidString: "1A2B3C4D-5E6F-4A7B-8C9D-0E1F2A3B4C5D") ?? UUID(), name: "Belasting",
                      colorKey: "blue")
    ]

    /// The tax letter with two open suggestions: the first person recognised by name (ticked from the start)
    /// and the label "Belasting" proposed by the AI.
    public static func detailWithSuggestions(id: UUID = UUID()) -> DocumentDetail {
        let base = detail(id: id)
        let summary = base.summary
        return DocumentDetail(
            summary: DocumentSummary(
                id: summary.id, clientID: summary.clientID, status: summary.status, pageCount: summary.pageCount,
                createdAt: summary.createdAt, sender: summary.sender, documentType: summary.documentType,
                letterDate: summary.letterDate, inboxState: .review, openSuggestionCount: 2
            ),
            failureCode: base.failureCode, summaryText: base.summaryText, summaryByAI: base.summaryByAI,
            pageTexts: base.pageTexts, proposals: base.proposals, tasks: base.tasks,
            suggestions: [
                Suggestion(
                    id: UUID(uuidString: "5C1E9F0A-2B3D-4E5F-8A6B-7C8D9E0F1A2B") ?? UUID(), action: .addAddressee,
                    targetID: persons[0].id, origin: .nameMatch, ruleName: "", quote: "J. de Wilde",
                    confidence: Decimal(string: "0.95") ?? 0, isPreselected: true
                ),
                Suggestion(
                    id: UUID(uuidString: "6D2F0A1B-3C4E-4F60-9B7C-8D9E0F1A2B3C") ?? UUID(), action: .addLabel,
                    targetID: labels[1].id, origin: .ai, ruleName: "", quote: "Belastingdienst",
                    confidence: Decimal(string: "0.7") ?? 0, isPreselected: false
                )
            ]
        )
    }

    public static func summary(
        id: UUID = UUID(), clientID: UUID = UUID(), status: DocumentStatus = .needsReview,
        sender: String = "", createdAt: Date = Date(timeIntervalSince1970: 1_794_650_400),
        inboxState: InboxState = .sorted
    ) -> DocumentSummary {
        DocumentSummary(
            id: id, clientID: clientID, status: status, pageCount: 1, createdAt: createdAt, sender: sender,
            documentType: "", letterDate: nil, inboxState: inboxState
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

    /// A letter in the trash, trashed on 2026-11-21 10:00 UTC; `purgeAfter` defaults to 30 days later.
    public static func trashed(
        id: UUID = UUID(), sender: String = "", by name: String = "",
        purgeAfter: Date = Date(timeIntervalSince1970: 1_797_847_200)
    ) -> TrashedDocument {
        TrashedDocument(
            summary: summary(id: id, status: .done, sender: sender),
            trashedAt: Date(timeIntervalSince1970: 1_795_255_200), trashedByName: name, purgeAfter: purgeAfter
        )
    }

    /// A pair of letters that look scanned twice, created on 2026-11-20 10:00 UTC, 92% alike.
    public static func pair(
        id: UUID = UUID(), first: DocumentSummary, second: DocumentSummary, suggestedKeep: UUID? = nil,
        differences: [DuplicateDifference] = [], twins: [TaskTwin] = [], canMerge: Bool = true
    ) -> DuplicatePair {
        DuplicatePair(
            id: id, createdAt: Date(timeIntervalSince1970: 1_795_168_800), first: first, second: second,
            suggestedKeepID: suggestedKeep ?? first.id, similarity: 92, same: [.sender], differences: differences,
            taskTwins: twins, canMerge: canMerge, blockedReason: canMerge ? "" : "visibility_differs"
        )
    }
}
