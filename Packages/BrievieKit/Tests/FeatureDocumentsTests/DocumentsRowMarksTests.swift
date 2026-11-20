import BrievieCore
@testable import FeatureDocuments
import Foundation
import Testing

/// What a row says about a letter the server read but nobody confirmed, and what the AI did by itself.
@MainActor
@Suite struct DocumentsRowMarksTests {
    private static let url = URL(string: "https://brievie.local") ?? URL(fileURLWithPath: "/")
    private static let arrival = Date(timeIntervalSince1970: 1_794_650_400)

    private let store = ConnectionStore(secrets: InMemorySecretStore())
    private let server = FakeDocumentServer { _, id in DocumentFixtures.detail(id: id) }

    private func rows(for documents: [DocumentSummary]) async throws -> [DocumentsModel.Row] {
        let connection = ServerConnection(urls: [Self.url], caCertificateDER: nil, deviceID: UUID(), userName: "J")
        try store.save(connection, token: "tok")
        server.onList { _ in documents }
        let model = DocumentsModel(
            documents: WorkspaceDocuments(workspaceID: UUID(), connection: connection, store: store, server: server),
            uploads: FakeUploadQueue(), canScan: true, camera: FakeScanCamera(.allowed), openSettings: {},
            onRevoked: {}, onMissingPairing: {}
        )
        await model.select(.all)
        return model.rows
    }

    private static func document(
        status: DocumentStatus, sender: String = "", confirmedByAI: Bool = false, autoLabels: [UUID] = []
    ) -> DocumentSummary {
        DocumentSummary(
            id: UUID(), clientID: UUID(), status: status, pageCount: 1, createdAt: arrival, sender: sender,
            documentType: "", letterDate: nil, confirmedByAI: confirmedByAI, autoLabelIDs: autoLabels
        )
    }

    /// The list has no sender before the review (the AI's proposal is only in the detail): the row says when the
    /// letter came in, so 26 letters to check no longer all read "Onbekende afzender".
    @Test func aLetterToCheckIsNamedByWhenItCameIn() async throws {
        let rows = try await rows(for: [Self.document(status: .needsReview), Self.document(status: .failed)])

        let expected = String(
            format: DocumentStrings.arrivedFormat, Self.arrival.formatted(date: .omitted, time: .shortened)
        )
        #expect(rows.map(\.title) == [expected, expected])
    }

    @Test func aConfirmedLetterWithoutSenderStaysUnknown() async throws {
        let rows = try await rows(for: [Self.document(status: .done)])

        #expect(rows.map(\.title) == [DocumentStrings.unknownSender])
    }

    @Test func aSenderAlwaysWins() async throws {
        let rows = try await rows(for: [Self.document(status: .needsReview, sender: "Wonen Voorbeeld")])

        #expect(rows.map(\.title) == ["Wonen Voorbeeld"])
    }

    @Test func whatTheAIDidByItselfIsMarkedAndSpoken() async throws {
        let rows = try await rows(for: [
            Self.document(status: .done, sender: "A", confirmedByAI: true),
            Self.document(status: .done, sender: "B", autoLabels: [UUID()]),
            Self.document(status: .done, sender: "C")
        ])

        let marked = rows.sorted { $0.title < $1.title }.map(\.isAutomatic)
        #expect(marked == [true, true, false])
        #expect(rows.first { $0.title == "A" }?.accessibilityLabel.contains(DocumentStrings.automaticByAI) == true)
    }

    @Test func theWordingIsTheWebs() throws {
        #expect(try CatalogParity.dutchValue(forKey: "documents.automatic", target: "FeatureDocuments")
            == "Automatisch door AI")
        #expect(DocumentStrings.automaticByAI == "Automatisch door AI")
        #expect(try CatalogParity.dutchValue(forKey: "documents.row.arrived", target: "FeatureDocuments")
            == DocumentStrings.arrivedFormat)
    }
}
