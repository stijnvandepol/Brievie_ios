import BrievieCore
@testable import FeatureDocuments
import Foundation
import Testing

/// A letter the AI confirmed, or put labels and names on, by itself says so, in the web's words.
@MainActor
@Suite struct ConfirmedAutomaticTests {
    private static let url = URL(string: "https://brievie.local") ?? URL(fileURLWithPath: "/")
    private let store = ConnectionStore(secrets: InMemorySecretStore())
    private let server = FakeDocumentServer { _, id in DocumentFixtures.detail(id: id, status: .done) }
    private let person = DocumentFixtures.persons[0]
    private let zorg = DocumentFixtures.labels[0]
    private let belasting = DocumentFixtures.labels[1]

    private func model(confirmedByAI: Bool = false, autoLabels: [UUID] = [], autoPersons: [UUID] = [])
        throws -> ConfirmedDocumentModel {
        let base = DocumentFixtures.detail(status: .done)
        let summary = base.summary
        let detail = DocumentDetail(
            summary: DocumentSummary(
                id: summary.id, clientID: summary.clientID, status: .done, pageCount: 1, createdAt: summary.createdAt,
                sender: "Wonen Voorbeeld", documentType: "other", letterDate: nil, addresseeIDs: [person.id],
                labelIDs: [zorg.id, belasting.id], confirmedByAI: confirmedByAI, autoLabelIDs: autoLabels,
                autoAddresseeIDs: autoPersons
            ),
            failureCode: "", summaryText: "", summaryByAI: false, pageTexts: [], proposals: [],
            tasks: [ConfirmedTask(
                id: UUID(), type: "pay", description: "Betalen", deadline: nil, deadlineSource: "manual",
                deadlineQuote: "", createdByAI: true
            )]
        )
        let connection = ServerConnection(urls: [Self.url], caCertificateDER: nil, deviceID: UUID(), userName: "J")
        try store.save(connection, token: "tok")
        return ConfirmedDocumentModel(
            detail: detail, persons: DocumentFixtures.persons, labels: DocumentFixtures.labels,
            documents: WorkspaceDocuments(workspaceID: UUID(), connection: connection, store: store, server: server),
            canEdit: true, onRevoked: {}, onMissingPairing: {}
        )
    }

    @Test func aLetterTheAIConfirmedSaysSo() throws {
        #expect(try model(confirmedByAI: true).isConfirmedByAI)
        #expect(try !model().isConfirmedByAI)
    }

    @Test func automaticLabelsAndNamesAreListedByName() throws {
        let model = try model(autoLabels: [belasting.id], autoPersons: [person.id])

        #expect(model.automaticLabelsNote == String(format: DocumentStrings.automaticAddedFormat, belasting.name))
        #expect(model.automaticAddresseesNote == String(
            format: DocumentStrings.automaticAddedFormat, person.displayName
        ))
    }

    @Test func nothingAutomaticSaysNothing() throws {
        let model = try model()

        #expect(model.automaticLabelsNote == nil)
        #expect(model.automaticAddresseesNote == nil)
    }

    @Test func aTaskTheAIMadeKeepsItsMark() throws {
        #expect(try model().tasks.map(\.createdByAI) == [true])
    }
}
