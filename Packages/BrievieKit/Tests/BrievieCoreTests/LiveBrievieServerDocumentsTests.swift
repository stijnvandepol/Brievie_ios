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

    private static let detailJSON = """
        {\(summaryJSON),"status":"needs_review","letter_date":"2026-11-03","failure_code":"",
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
            [{\(Self.summaryJSON),"status":"needs_review","letter_date":"2026-11-03"},
             {\(Self.summaryJSON),"status":"archived","letter_date":null}]
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
        (403, "forbidden", ServerError.other("http_403")),
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
            [{"id":"geen-uuid","client_id":"x","status":"done","page_count":1,
              "created_at":"2026-11-14T10:00:00Z","sender":"","document_type":"","letter_date":null}]
            """))

        await #expect(throws: ServerError.incompatible) {
            try await server.documents(in: scope(url))
        }
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
