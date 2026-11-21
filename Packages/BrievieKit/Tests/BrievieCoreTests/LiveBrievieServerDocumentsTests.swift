@testable import BrievieCore
import Foundation
import Testing

/// The document calls of `LiveBrievieServer` against `StubURLProtocol`.
@Suite struct LiveBrievieServerDocumentsTests {
    private let server = LiveBrievieServer(configuration: StubURLProtocol.configuration)
    private static let workspaceID = UUID(uuidString: "71673A98-9DD7-4023-A848-FEA48B8AA912") ?? UUID()
    private static let documentID = UUID(uuidString: "D6311302-19AE-4D0B-AB51-A3BDDE16E78A") ?? UUID()
    private static let base = "/api/v1/workspaces/71673a98-9dd7-4023-a848-fea48b8aa912/documents"

    private static let summaryJSON = """
        "id":"d6311302-19ae-4d0b-ab51-a3bdde16e78a","client_id":"0b7f6b0e-6a5d-4c59-9d0e-0d6a3c3b9a11",
        "page_count":2,"created_at":"2026-11-14T10:00:00.123456Z","sender":"Belastingdienst",
        "document_type":"assessment"
        """

    /// The fields phase 1c added to every document; a 1b server leaves them out.
    private static let organiseJSON = """
        "addressee_ids":[],"label_ids":[],"inbox_state":"review","open_suggestion_count":0
        """

    private static let detailJSON = """
        {\(summaryJSON),\(organiseJSON),"suggestions":[],
         "status":"needs_review","letter_date":"2026-11-03","failure_code":"",
         "summary":"Je moet betalen.","summary_by_ai":true,
         "pages":[{"index":2,"ocr_text":"twee"},{"index":1,"ocr_text":"een"}],
         "proposals":[{"field":"action_deadline","group":1,"value":"2026-12-01","quote":"vóór 1 december 2026",
                       "confidence":"0.920","needs_attention":false,"provider":"api.mistral.ai","model":"m"}],
         "tasks":[{"id":"8520f89b-c359-420c-b156-617624b31eb8","type":"pay","description":"Betalen",
                   "deadline":"2026-12-01","deadline_source":"in_document",
                   "deadline_quote":"vóór 1 december 2026","status":"open"}]}
        """

    private func scope(_ url: URL) -> DocumentScope {
        DocumentScope(
            url: url, trust: ServerTrust(caCertificateDER: nil), token: "tok", workspaceID: Self.workspaceID
        )
    }

    @Test func listMapsEveryFieldAndUnknownStatus() async throws {
        let url = try StubURLProtocol.serve(.response(status: 200, json: """
            [{\(Self.summaryJSON),\(Self.organiseJSON),"status":"needs_review","letter_date":"2026-11-03"},
             {\(Self.summaryJSON),\(Self.organiseJSON),"status":"archived","letter_date":null}]
            """))

        let documents = try await server.documents(in: scope(url))

        #expect(documents.count == 2)
        let first = try #require(documents.first)
        #expect(first.id == Self.documentID)
        #expect(first.clientID == UUID(uuidString: "0B7F6B0E-6A5D-4C59-9D0E-0D6A3C3B9A11"))
        #expect(first.status == .needsReview)
        #expect(first.pageCount == 2)
        #expect(first.sender == "Belastingdienst")
        #expect(first.documentType == "assessment")
        #expect(first.letterDate == CalendarDate(year: 2026, month: 11, day: 3))
        #expect(abs(first.createdAt.timeIntervalSince1970 - 1_794_650_400.123) < 0.01)
        #expect(documents[1].status == .unknown)
        #expect(documents[1].letterDate == nil)

        let request = try #require(StubURLProtocol.requests(to: url).first)
        #expect(request.url?.path() == Self.base)
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer tok")
    }

    @Test func detailMapsPagesProposalsAndTasks() async throws {
        let url = try StubURLProtocol.serve(.response(status: 200, json: Self.detailJSON))

        let detail = try await server.document(Self.documentID, in: scope(url))

        #expect(detail.summary.status == .needsReview)
        #expect(detail.summaryText == "Je moet betalen.")
        #expect(detail.summaryByAI)
        #expect(detail.failureCode.isEmpty)
        #expect(detail.pageTexts == ["een", "twee"])
        let confidence = try #require(Decimal(string: "0.92"))
        #expect(detail.proposals == [Proposal(
            field: "action_deadline", group: 1, value: "2026-12-01", quote: "vóór 1 december 2026",
            confidence: confidence, needsAttention: false, provider: "api.mistral.ai", model: "m"
        )])
        let task = try #require(detail.tasks.first)
        #expect(task.type == "pay")
        #expect(task.deadline == CalendarDate(year: 2026, month: 12, day: 1))
        #expect(task.deadlineSource == "in_document")
        #expect(task.deadlineQuote == "vóór 1 december 2026")
        #expect(StubURLProtocol.requests(to: url).first?.url?.path()
            == "\(Self.base)/d6311302-19ae-4d0b-ab51-a3bdde16e78a")
    }

    @Test func confirmSendsCalendarDatesAndLeavesOutMissingOnes() async throws {
        let url = try StubURLProtocol.serve(.response(status: 200, json: Self.detailJSON))
        let review = ConfirmedReview(
            sender: "Belastingdienst", documentType: "assessment", letterDate: nil, summary: "Je moet betalen.",
            summaryByAI: true,
            tasks: [
                TaskDraft(
                    type: "pay", description: "Betalen", deadline: CalendarDate(year: 2026, month: 12, day: 1),
                    deadlineSource: "in_document", deadlineQuote: "vóór 1 december 2026", needsAttention: false
                ),
                TaskDraft(
                    type: "respond", description: "Bellen", deadline: nil, deadlineSource: "manual",
                    deadlineQuote: "", needsAttention: false
                )
            ]
        )

        _ = try await server.confirm(Self.documentID, review: review, in: scope(url))

        let request = try #require(StubURLProtocol.requests(to: url).first)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.path() == "\(Self.base)/d6311302-19ae-4d0b-ab51-a3bdde16e78a/confirm")
        let sent = try #require(request.httpBody)
        let body = try #require(JSONSerialization.jsonObject(with: sent) as? [String: Any])
        #expect(body["letter_date"] == nil)
        #expect(body["sender"] as? String == "Belastingdienst")
        #expect(body["summary_by_ai"] as? Bool == true)
        let tasks = try #require(body["tasks"] as? [[String: Any]])
        #expect(tasks[0]["deadline"] as? String == "2026-12-01")
        #expect(tasks[0]["deadline_source"] as? String == "in_document")
        #expect(tasks[0]["deadline_quote"] as? String == "vóór 1 december 2026")
        #expect(tasks[1]["deadline"] == nil)
        #expect(tasks[1]["type"] as? String == "respond")
    }

    @Test func retryPostsAndReturnsTheDocument() async throws {
        let url = try StubURLProtocol.serve(.response(status: 202, json: Self.detailJSON))

        let detail = try await server.retryProcessing(Self.documentID, in: scope(url))

        #expect(detail.summary.id == Self.documentID)
        let request = try #require(StubURLProtocol.requests(to: url).first)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.path() == "\(Self.base)/d6311302-19ae-4d0b-ab51-a3bdde16e78a/retry")
    }

    @Test func pageImageReturnsTheBytes() async throws {
        let jpeg = Data([0xFF, 0xD8, 0xFF, 1, 2, 3])
        let url = try StubURLProtocol.serve(.data(status: 200, contentType: "image/jpeg", body: jpeg))

        let data = try await server.pageImage(document: Self.documentID, index: 2, in: scope(url))

        #expect(data == jpeg)
        #expect(StubURLProtocol.requests(to: url).first?.url?.path()
            == "\(Self.base)/d6311302-19ae-4d0b-ab51-a3bdde16e78a/pages/2")
    }

    @Test func oversizedPageImageIsRefused() async throws {
        let huge = Data(count: LiveBrievieServer.maxPageImageBytes + 1)
        let url = try StubURLProtocol.serve(.data(status: 200, contentType: "image/jpeg", body: huge))

        await #expect(throws: ServerError.incompatible) {
            try await server.pageImage(document: Self.documentID, index: 1, in: scope(url))
        }
    }

    @Test(arguments: [
        (401, "not_authenticated", ServerError.unauthorized),
        (404, "document_not_found", ServerError.other("document_not_found")),
        (404, "workspace_not_found", ServerError.other("workspace_not_found")),
        (409, "document_not_reviewable", ServerError.other("document_not_reviewable")),
        (422, "validation_error", ServerError.other("validation_error")),
        (403, "forbidden", ServerError.other("forbidden")),
        (403, "not_ours", ServerError.other("http_403")),
        (500, "internal_error", ServerError.other("http_500"))
    ])
    func refusalsAreMapped(status: Int, code: String, expected: ServerError) async throws {
        let url = try StubURLProtocol.serve(.response(status: status, json: #"{"code":"\#(code)","message":"x"}"#))
        let review = ConfirmedReview(
            sender: "", documentType: "", letterDate: nil, summary: "", summaryByAI: false, tasks: []
        )

        await #expect(throws: expected) {
            try await server.confirm(Self.documentID, review: review, in: scope(url))
        }
    }

    @Test(arguments: [
        (404, "page_not_found", ServerError.other("page_not_found")),
        (409, "document_not_failed", ServerError.other("document_not_failed"))
    ])
    func otherCallsMapRefusalsToo(status: Int, code: String, expected: ServerError) async throws {
        let url = try StubURLProtocol.serve(.response(status: status, json: #"{"code":"\#(code)","message":"x"}"#))

        await #expect(throws: expected) {
            if status == 404 {
                _ = try await server.pageImage(document: Self.documentID, index: 9, in: scope(url))
            } else {
                _ = try await server.retryProcessing(Self.documentID, in: scope(url))
            }
        }
    }

    @Test func malformedIdentifierIsIncompatible() async throws {
        let url = try StubURLProtocol.serve(.response(status: 200, json: """
            [{"id":"geen-uuid","client_id":"0b7f6b0e-6a5d-4c59-9d0e-0d6a3c3b9a11","status":"done","page_count":1,
              "created_at":"2026-11-14T10:00:00Z","sender":"","document_type":"","letter_date":null,
              \(Self.organiseJSON)}]
            """))

        await #expect(throws: ServerError.incompatible) {
            try await server.documents(in: scope(url))
        }
    }

    @Test func unreadableAddresseeIDIsIncompatible() async throws {
        let url = try StubURLProtocol.serve(.response(status: 200, json: """
            [{\(Self.summaryJSON),"status":"done","letter_date":null,"addressee_ids":["geen-uuid"],"label_ids":[],
              "inbox_state":"","open_suggestion_count":0}]
            """))

        await #expect(throws: ServerError.incompatible) {
            try await server.documents(in: scope(url))
        }
    }
}

// MARK: - Phase 1c: organising

extension LiveBrievieServerDocumentsTests {
    private static let personID = "3f0c8a52-6d0e-4c8e-9a51-1e2b3c4d5e6f"
    private static let labelID = "9a8b7c6d-5e4f-4a3b-8c2d-1e0f9a8b7c6d"
    private static let otherLabelID = "1a2b3c4d-5e6f-4a7b-8c9d-0e1f2a3b4c5d"

    /// A detail as a 1b server writes it: none of the organise fields.
    private static let detail1bJSON = """
        {\(summaryJSON),"status":"needs_review","letter_date":null,"failure_code":"","summary":"",
         "summary_by_ai":false,
         "pages":[{"index":1,"ocr_text":"een"}],"proposals":[],"tasks":[]}
        """

    private func suggestionJSON(
        action: String, labelID: String? = nil, personID: String? = nil, origin: String = "rule"
    ) -> String {
        """
        {"id":"\(UUID().uuidString.lowercased())","action":"\(action)",
         "label_id":\(labelID.map { #""\#($0)""# } ?? "null"),"person_id":\(personID.map { #""\#($0)""# } ?? "null"),
         "origin":"\(origin)","rule_name":"Zorg","quote":"zorgtoeslag","confidence":"0.800","preselected":false}
        """
    }

    @Test func decodesDocumentWithoutOrganiseFields() async throws {
        let url = try StubURLProtocol.serve(.response(status: 200, json: Self.detail1bJSON))

        let detail = try await server.document(Self.documentID, in: scope(url))

        // Without an inbox state the server is on 1b: the state follows from the status.
        #expect(detail.summary.inboxState == .review)
        #expect(detail.summary.addresseeIDs.isEmpty)
        #expect(detail.summary.labelIDs.isEmpty)
        #expect(detail.summary.openSuggestionCount == 0)
        #expect(detail.suggestions.isEmpty)
        #expect(detail.pageTexts == ["een"])
    }

    @Test func decodesA1bDocumentList() async throws {
        let statuses = ["processing", "needs_review", "failed", "done", "archived"]
        let url = try StubURLProtocol.serve(.response(status: 200, json: "[" + statuses.map { status in
            #"{\#(Self.summaryJSON),"status":"\#(status)","letter_date":null}"#
        }.joined(separator: ",") + "]"))

        let documents = try await server.documents(in: scope(url))

        #expect(documents.map(\.inboxState) == [.new, .review, .review, .sorted, .unknown])
        #expect(documents.allSatisfy { $0.addresseeIDs.isEmpty && $0.labelIDs.isEmpty })
        #expect(documents.allSatisfy { $0.openSuggestionCount == 0 })
    }

    @Test func decodesSummaryWithAddresseesLabelsAndInboxState() async throws {
        let url = try StubURLProtocol.serve(.response(status: 200, json: """
            [{\(Self.summaryJSON),"status":"done","letter_date":null,
              "addressee_ids":["\(Self.personID)"],"label_ids":["\(Self.labelID)","\(Self.otherLabelID)"],
              "inbox_state":"new","open_suggestion_count":2}]
            """))

        let summary = try #require(try await server.documents(in: scope(url)).first)

        #expect(summary.inboxState == .new)
        #expect(summary.addresseeIDs == [UUID(uuidString: Self.personID)])
        #expect(summary.labelIDs == [UUID(uuidString: Self.labelID), UUID(uuidString: Self.otherLabelID)])
        #expect(summary.openSuggestionCount == 2)
    }

    @Test func unknownSuggestionActionIsDropped() async throws {
        let suggestions = [
            suggestionJSON(action: "add_label", labelID: Self.labelID, origin: "ai"),
            suggestionJSON(action: "move_to_folder", labelID: Self.labelID),
            suggestionJSON(action: "add_addressee", personID: nil),
            suggestionJSON(action: "add_addressee", personID: Self.personID, origin: "telepathy")
        ].joined(separator: ",")
        let url = try StubURLProtocol.serve(.response(status: 200, json: """
            {\(Self.summaryJSON),\(Self.organiseJSON),"suggestions":[\(suggestions)],"status":"needs_review",
             "letter_date":null,"failure_code":"","summary":"","summary_by_ai":false,"pages":[],"proposals":[],
             "tasks":[]}
            """))

        let detail = try await server.document(Self.documentID, in: scope(url))

        #expect(detail.suggestions.map(\.action) == [.addLabel, .addAddressee])
        let label = try #require(detail.suggestions.first)
        #expect(label.targetID == UUID(uuidString: Self.labelID))
        #expect(label.origin == .ai)
        #expect(label.ruleName == "Zorg")
        #expect(label.quote == "zorgtoeslag")
        #expect(label.confidence == Decimal(string: "0.8"))
        #expect(!label.isPreselected)
        #expect(detail.suggestions.last?.targetID == UUID(uuidString: Self.personID))
        #expect(detail.suggestions.last?.origin == .unknown)
    }

    @Test func unknownInboxStateBecomesUnknown() async throws {
        let url = try StubURLProtocol.serve(.response(status: 200, json: """
            [{\(Self.summaryJSON),"status":"done","letter_date":null,"addressee_ids":[],"label_ids":[],
              "inbox_state":"snoozed","open_suggestion_count":0}]
            """))

        let summary = try #require(try await server.documents(in: scope(url)).first)

        #expect(summary.inboxState == .unknown)
    }

    private func sentConfirm(_ review: ConfirmedReview) async throws -> [String: Any] {
        let url = try StubURLProtocol.serve(.response(status: 200, json: Self.detailJSON))
        _ = try await server.confirm(Self.documentID, review: review, in: scope(url))
        let sent = try #require(StubURLProtocol.requests(to: url).first?.httpBody)
        return try #require(JSONSerialization.jsonObject(with: sent) as? [String: Any])
    }

    @Test func confirmSendsOrganisationWhenSet() async throws {
        let person = try #require(UUID(uuidString: Self.personID))
        let labels = try [Self.labelID, Self.otherLabelID].map { try #require(UUID(uuidString: $0)) }
        let review = ConfirmedReview(
            sender: "CAK", documentType: "bill", letterDate: CalendarDate(year: 2026, month: 11, day: 3),
            summary: "Je moet betalen.", summaryByAI: true,
            tasks: [TaskDraft(
                type: "pay", description: "Betalen", deadline: nil, deadlineSource: "manual", deadlineQuote: "",
                needsAttention: false
            )],
            addresseeIDs: [person], labelIDs: labels, setsOrganisation: true
        )

        let body = try await sentConfirm(review)

        #expect(body["sets_organisation"] as? Bool == true)
        #expect(body["addressee_ids"] as? [String] == [Self.personID])
        #expect(body["label_ids"] as? [String] == [Self.labelID, Self.otherLabelID])
        // Every 1b field is still there, so a 1b server (which ignores unknown fields) accepts it.
        #expect(body["sender"] as? String == "CAK")
        #expect(body["document_type"] as? String == "bill")
        #expect(body["letter_date"] as? String == "2026-11-03")
        #expect(body["summary"] as? String == "Je moet betalen.")
        #expect(body["summary_by_ai"] as? Bool == true)
        #expect((body["tasks"] as? [[String: Any]])?.first?["type"] as? String == "pay")
    }

    @Test func confirmWithoutOrganisationSendsFlagFalse() async throws {
        let review = ConfirmedReview(
            sender: "CAK", documentType: "bill", letterDate: nil, summary: "", summaryByAI: false, tasks: []
        )

        let body = try await sentConfirm(review)

        #expect(body["sets_organisation"] as? Bool == false)
        #expect(body["addressee_ids"] as? [String] == [])
        #expect(body["label_ids"] as? [String] == [])
    }
}

@Suite struct CalendarDateTests {
    @Test func parsesAndPrintsISODates() {
        let date = CalendarDate(iso: "2026-12-01")

        #expect(date == CalendarDate(year: 2026, month: 12, day: 1))
        #expect(date?.iso == "2026-12-01")
        #expect(CalendarDate(year: 2026, month: 3, day: 7).iso == "2026-03-07")
    }

    @Test(arguments: ["", "1 december", "2026-13-01", "2026-02-30", "2026-12-01T10:00:00Z", "26-12-01"])
    func refusesWhatIsNotADate(text: String) {
        #expect(CalendarDate(iso: text) == nil)
    }

    @Test func dayDoesNotMoveWithTheTimeZone() throws {
        // A deadline is a day, not a moment (spec 19).
        let date = CalendarDate(year: 2026, month: 11, day: 3)
        for identifier in ["America/Los_Angeles", "Pacific/Auckland", "Europe/Amsterdam"] {
            let zone = try #require(TimeZone(identifier: identifier))
            #expect(CalendarDate(date.date(in: zone), in: zone) == date)
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = zone
            #expect(calendar.component(.day, from: date.date(in: zone)) == 3)
        }
    }

    @Test func comparesByDay() {
        #expect(CalendarDate(year: 2026, month: 11, day: 30) < CalendarDate(year: 2026, month: 12, day: 1))
        #expect(CalendarDate(year: 2026, month: 12, day: 1) < CalendarDate(year: 2027, month: 1, day: 1))
    }
}
