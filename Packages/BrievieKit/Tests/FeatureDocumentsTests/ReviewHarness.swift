import BrievieCore
@testable import FeatureDocuments
import Foundation

/// A review model against a fake server, shared by the suites below.
@MainActor
struct ReviewHarness {
    private static let url = URL(string: "https://brievie.local") ?? URL(fileURLWithPath: "/")

    let documentID = UUID()
    let store = ConnectionStore(secrets: InMemorySecretStore())
    let server = FakeDocumentServer { _, id in DocumentFixtures.detail(id: id) }
    let events = EventLog()

    /// 19 November 2026, 10:00 in Amsterdam: the day an empty letter date starts as.
    static let clock = TodayClock(
        now: { Date(timeIntervalSince1970: 1_795_078_800) },
        timeZone: { TimeZone(identifier: "Europe/Amsterdam") ?? .gmt }
    )

    func model(canEdit: Bool = true, clock: TodayClock = ReviewHarness.clock) throws -> ReviewModel {
        let connection = ServerConnection(
            urls: [Self.url], caCertificateDER: nil, deviceID: UUID(), userName: "Stijn"
        )
        try store.save(connection, token: "tok")
        return ReviewModel(
            documentID: documentID,
            documents: WorkspaceDocuments(
                workspaceID: UUID(), connection: connection, store: store, server: server
            ),
            canEdit: canEdit,
            onRevoked: { [events] in events.add("revoked") },
            onMissingPairing: { [events] in events.add("missing") },
            clock: clock
        )
    }

    func answer(_ detail: @escaping @Sendable (UUID) -> DocumentDetail) {
        server.onDetail { _, id in detail(id) }
    }
}
