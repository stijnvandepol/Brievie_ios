@testable import BrievieCore
import Foundation
import Testing

/// The organise calls of `LiveBrievieServer` (persons, labels, addressees, suggestions) against `StubURLProtocol`.
@Suite struct LiveBrievieServerOrganiseTests {
    private let server = LiveBrievieServer(configuration: StubURLProtocol.configuration)
    private static let workspaceID = UUID(uuidString: "71673A98-9DD7-4023-A848-FEA48B8AA912") ?? UUID()
    private static let documentID = UUID(uuidString: "D6311302-19AE-4D0B-AB51-A3BDDE16E78A") ?? UUID()
    private static let suggestionID = UUID(uuidString: "5C1E9F0A-2B3D-4E5F-8A6B-7C8D9E0F1A2B") ?? UUID()
    private static let workspacePath = "/api/v1/workspaces/71673a98-9dd7-4023-a848-fea48b8aa912"
    private static let documentPath = "\(workspacePath)/documents/d6311302-19ae-4d0b-ab51-a3bdde16e78a"
    private static let personID = "3f0c8a52-6d0e-4c8e-9a51-1e2b3c4d5e6f"
    private static let otherPersonID = "7e6d5c4b-3a29-4180-9f7e-6d5c4b3a2918"
    private static let labelID = "9a8b7c6d-5e4f-4a3b-8c2d-1e0f9a8b7c6d"

    private static let personJSON = """
        {"id":"\(personID)","display_name":"Stijn","name_variants":["S. van de Pol"],"user_id":null,
         "archived":false,"document_count":3}
        """

    private static let labelJSON = """
        {"id":"\(labelID)","name":"Zorg","color":"green","system_key":"","document_count":1}
        """

    private static let detailJSON = """
        {"id":"d6311302-19ae-4d0b-ab51-a3bdde16e78a","client_id":"0b7f6b0e-6a5d-4c59-9d0e-0d6a3c3b9a11",
         "status":"done","page_count":1,"created_at":"2026-11-14T10:00:00Z","sender":"CAK","document_type":"bill",
         "letter_date":null,"addressee_ids":["\(personID)","\(otherPersonID)"],"label_ids":["\(labelID)"],
         "inbox_state":"","open_suggestion_count":0,"failure_code":"","summary":"","summary_by_ai":false,
         "pages":[],"proposals":[],"tasks":[],"suggestions":[]}
        """

    private func scope(_ url: URL) -> DocumentScope {
        DocumentScope(
            url: url, trust: ServerTrust(caCertificateDER: nil), token: "tok", workspaceID: Self.workspaceID
        )
    }

    private func uuid(_ text: String) throws -> UUID {
        try #require(UUID(uuidString: text))
    }

    @Test(arguments: [
        (DocumentFilter.all, [String: String]()),
        (DocumentFilter(inboxState: .unassigned), ["inbox_state": "unassigned"]),
        (
            DocumentFilter(inboxState: .unassigned, personID: UUID(uuidString: personID)),
            ["inbox_state": "unassigned", "person_id": personID]
        ),
        (DocumentFilter(personID: UUID(uuidString: personID)), ["person_id": personID])
    ])
    func listSendsInboxStateAndPersonAsQuery(filter: DocumentFilter, expected: [String: String]) async throws {
        let url = try StubURLProtocol.serve(.response(status: 200, json: "[]"))

        _ = try await server.documents(in: scope(url), filter: filter)

        let request = try #require(StubURLProtocol.requests(to: url).first)
        #expect(request.url?.path() == "\(Self.workspacePath)/documents")
        let components = try #require(request.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) })
        let query = Dictionary(
            (components.queryItems ?? []).map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { first, _ in first }
        )
        #expect(query == expected)
    }

    @Test func setAddresseesSendsExactIDsAndReturnsDetail() async throws {
        let url = try StubURLProtocol.serve(.response(status: 200, json: Self.detailJSON))
        let ids = try [uuid(Self.personID), uuid(Self.otherPersonID)]

        let detail = try await server.setAddressees(ids, document: Self.documentID, in: scope(url))

        #expect(detail.summary.addresseeIDs == ids)
        #expect(detail.summary.inboxState == .sorted)
        let request = try #require(StubURLProtocol.requests(to: url).first)
        #expect(request.httpMethod == "PUT")
        #expect(request.url?.path() == "\(Self.documentPath)/addressees")
        let sent = try #require(request.httpBody)
        let body = try #require(JSONSerialization.jsonObject(with: sent) as? [String: Any])
        #expect(body.count == 1)
        #expect(body["person_ids"] as? [String] == [Self.personID, Self.otherPersonID])
    }

    @Test func setLabelsSendsExactIDs() async throws {
        let url = try StubURLProtocol.serve(.response(status: 200, json: Self.detailJSON))

        let detail = try await server.setLabels([uuid(Self.labelID)], document: Self.documentID, in: scope(url))

        #expect(detail.summary.labelIDs == [try uuid(Self.labelID)])
        let request = try #require(StubURLProtocol.requests(to: url).first)
        #expect(request.httpMethod == "PUT")
        #expect(request.url?.path() == "\(Self.documentPath)/labels")
        let sent = try #require(request.httpBody)
        let body = try #require(JSONSerialization.jsonObject(with: sent) as? [String: Any])
        #expect(body["label_ids"] as? [String] == [Self.labelID])
    }

    @Test func personsAndLabelsAreMapped() async throws {
        let personsURL = try StubURLProtocol.serve(.response(status: 200, json: "[\(Self.personJSON)]"))
        let labelsURL = try StubURLProtocol.serve(.response(status: 200, json: "[\(Self.labelJSON)]"))

        let persons = try await server.persons(in: scope(personsURL))
        let labels = try await server.labels(in: scope(labelsURL))

        #expect(persons == [Person(
            id: try uuid(Self.personID), displayName: "Stijn", nameVariants: ["S. van de Pol"], isArchived: false
        )])
        #expect(labels == [DocumentLabel(id: try uuid(Self.labelID), name: "Zorg", colorKey: "green")])
        #expect(StubURLProtocol.requests(to: personsURL).first?.url?.path() == "\(Self.workspacePath)/persons")
        #expect(StubURLProtocol.requests(to: labelsURL).first?.url?.path() == "\(Self.workspacePath)/labels")
    }

    @Test func createPersonPostsTheName() async throws {
        let url = try StubURLProtocol.serve(.response(status: 201, json: Self.personJSON))

        let person = try await server.createPerson(named: "Stijn", in: scope(url))

        #expect(person.id == (try uuid(Self.personID)))
        let request = try #require(StubURLProtocol.requests(to: url).first)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.path() == "\(Self.workspacePath)/persons")
        let sent = try #require(request.httpBody)
        let body = try #require(JSONSerialization.jsonObject(with: sent) as? [String: Any])
        #expect(body["display_name"] as? String == "Stijn")
    }

    @Test func acceptAndDismissPostToTheSuggestion() async throws {
        let accept = try StubURLProtocol.serve(.response(status: 200, json: Self.detailJSON))
        let dismiss = try StubURLProtocol.serve(.response(status: 200, json: Self.detailJSON))

        _ = try await server.acceptSuggestion(Self.suggestionID, document: Self.documentID, in: scope(accept))
        _ = try await server.dismissSuggestion(Self.suggestionID, document: Self.documentID, in: scope(dismiss))

        let suggestionPath = "\(Self.documentPath)/suggestions/5c1e9f0a-2b3d-4e5f-8a6b-7c8d9e0f1a2b"
        #expect(StubURLProtocol.requests(to: accept).first?.httpMethod == "POST")
        #expect(StubURLProtocol.requests(to: accept).first?.url?.path() == "\(suggestionPath)/accept")
        #expect(StubURLProtocol.requests(to: dismiss).first?.url?.path() == "\(suggestionPath)/dismiss")
    }

    @Test func personExistsMapsToNameTaken() async throws {
        let url = try StubURLProtocol.serve(.response(status: 409, json: #"{"code":"person_exists","message":"x"}"#))
        let store = ConnectionStore(secrets: InMemorySecretStore())
        let connection = ServerConnection(urls: [url], caCertificateDER: nil, deviceID: UUID(), userName: "Stijn")
        try store.save(connection, token: "tok")
        let documents = WorkspaceDocuments(
            workspaceID: Self.workspaceID, connection: connection, store: store, server: server
        )

        await #expect(throws: DocumentsError.nameTaken) { try await documents.createPerson(named: "Stijn") }
    }

    @Test(arguments: [
        (404, "person_not_found", ServerError.other("person_not_found")),
        (404, "label_not_found", ServerError.other("label_not_found")),
        (404, "suggestion_not_found", ServerError.other("suggestion_not_found")),
        (409, "document_processing", ServerError.other("document_processing")),
        (409, "person_exists", ServerError.other("person_exists"))
    ])
    func newCodesPassThrough(status: Int, code: String, expected: ServerError) async throws {
        let url = try StubURLProtocol.serve(.response(status: status, json: #"{"code":"\#(code)","message":"x"}"#))

        await #expect(throws: expected) {
            try await server.setLabels([], document: Self.documentID, in: scope(url))
        }
    }

    @Test func everyNewCallCarriesTheBearerToken() async throws {
        let persons = try StubURLProtocol.serve(.response(status: 200, json: "[]"))
        let create = try StubURLProtocol.serve(.response(status: 201, json: Self.personJSON))
        let labels = try StubURLProtocol.serve(.response(status: 200, json: "[]"))
        let filtered = try StubURLProtocol.serve(.response(status: 200, json: "[]"))
        let documentCalls = try (0..<4).map { _ in
            try StubURLProtocol.serve(.response(status: 200, json: Self.detailJSON))
        }

        _ = try await server.persons(in: scope(persons))
        _ = try await server.createPerson(named: "Stijn", in: scope(create))
        _ = try await server.labels(in: scope(labels))
        _ = try await server.documents(in: scope(filtered), filter: DocumentFilter(inboxState: .new))
        _ = try await server.setAddressees([], document: Self.documentID, in: scope(documentCalls[0]))
        _ = try await server.setLabels([], document: Self.documentID, in: scope(documentCalls[1]))
        _ = try await server.acceptSuggestion(Self.suggestionID, document: Self.documentID, in: scope(documentCalls[2]))
        _ = try await server.dismissSuggestion(
            Self.suggestionID, document: Self.documentID, in: scope(documentCalls[3])
        )

        for url in [persons, create, labels, filtered] + documentCalls {
            let request = try #require(StubURLProtocol.requests(to: url).first)
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer tok")
        }
    }
}
