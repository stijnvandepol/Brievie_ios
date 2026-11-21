import BrievieCore
@testable import FeatureDocuments
import Foundation
import Testing

/// The Prullenbak screen: days left, who deleted a letter, the server's retention and cap, restoring.
@MainActor
@Suite struct TrashModelTests {
    private static let url = URL(string: "https://brievie.local") ?? URL(fileURLWithPath: "/")
    private nonisolated static let amsterdam = TimeZone(identifier: "Europe/Amsterdam") ?? .gmt
    private static let dutch = Locale(identifier: "nl_NL")

    /// 21 November 2026, 23:30 in Amsterdam (22:30 UTC).
    private static let lateEvening = TodayClock(
        now: { Date(timeIntervalSince1970: 1_795_300_200) }, timeZone: { TrashModelTests.amsterdam }
    )

    private let store = ConnectionStore(secrets: InMemorySecretStore())
    private let server = FakeDocumentServer { _, id in DocumentFixtures.detail(id: id) }
    private let events = EventLog()

    private func model(canRestore: Bool = true) throws -> TrashModel {
        let connection = ServerConnection(
            urls: [Self.url], caCertificateDER: nil, deviceID: UUID(), userName: "Stijn"
        )
        try store.save(connection, token: "tok")
        return TrashModel(
            documents: WorkspaceDocuments(workspaceID: UUID(), connection: connection, store: store, server: server),
            canRestore: canRestore, clock: Self.lateEvening, locale: Self.dutch,
            onRestored: { [events] _ in events.add("restored") },
            onRevoked: { [events] in events.add("revoked") },
            onMissingPairing: { [events] in events.add("missing") }
        )
    }

    /// A UTC instant on a day of November or December 2026.
    private nonisolated static func utc(month: Int, day: Int, hour: Int) -> Date {
        var components = DateComponents(year: 2026, month: month, day: day, hour: hour)
        components.timeZone = .gmt
        return Calendar(identifier: .gregorian).date(from: components) ?? .distantPast
    }

    private nonisolated static func trashed(
        id: UUID = UUID(), sender: String = "CAK", by name: String = "", on day: Int = 9,
        purgeAfter: Date = utc(month: 12, day: 9, hour: 10)
    ) -> TrashedDocument {
        TrashedDocument(
            summary: DocumentFixtures.summary(id: id, status: .done, sender: sender),
            trashedAt: utc(month: 11, day: day, hour: 10), trashedByName: name, purgeAfter: purgeAfter
        )
    }

    @Test func daysLeftCountsCalendarDaysInTheLocalTimeZone() {
        let purge = Self.utc(month: 12, day: 3, hour: 10)

        #expect(TrashModel.daysLeft(until: purge, clock: Self.lateEvening) == 12)
    }

    @Test func aPurgeDayTodayOrPastSaysErasedToday() async throws {
        let ids = (0..<4).map { _ in UUID() }
        let purges = [
            Self.utc(month: 11, day: 21, hour: 20), Self.utc(month: 11, day: 20, hour: 9),
            Self.utc(month: 11, day: 22, hour: 9), Self.utc(month: 12, day: 3, hour: 10)
        ]
        server.onTrashList { _ in
            TrashList(items: zip(ids, purges).map { Self.trashed(id: $0, purgeAfter: $1) })
        }
        let model = try model()

        await model.load()

        #expect(model.rows.map(\.daysLeftLine) == [
            "Wordt vandaag gewist", "Wordt vandaag gewist", "Nog 1 dag", "Nog 12 dagen"
        ])
    }

    @Test func rowsSayWhoDeletedTheLetter() async throws {
        server.onTrashList { _ in
            TrashList(items: [Self.trashed(by: "Anna", on: 9), Self.trashed(by: "", on: 8)])
        }
        let model = try model()

        await model.load()

        #expect(model.rows.map(\.deletedLine) == [
            "Verwijderd op 9 november 2026 door Anna", "Verwijderd op 8 november 2026"
        ])
    }

    @Test func aLetterWithoutSenderIsUnknownSender() async throws {
        server.onTrashList { _ in TrashList(items: [Self.trashed(sender: "")]) }
        let model = try model()

        await model.load()

        #expect(model.rows.map(\.title) == [DocumentStrings.unknownSender])
    }

    @Test func theIntroNamesTheServersRetention() async throws {
        server.onTrashList { _ in TrashList(items: [], retentionDays: 30) }
        let model = try model()

        await model.load()

        #expect(model.intro == "Brieven in de prullenbak worden na 30 dagen voorgoed gewist. "
            + "Tot die tijd kun je ze terugzetten.")
        #expect(model.webOnlyNote == "Definitief verwijderen en de prullenbak legen kan alleen in de webinterface.")
    }

    @Test func aCapNoteWhenTheServerHasMore() async throws {
        let items = (0..<500).map { _ in Self.trashed() }
        server.onTrashList { _ in TrashList(items: items, total: 501) }
        let capped = try model()
        await capped.load()
        #expect(capped.capNote == "Alleen de nieuwste 500 worden getoond.")

        server.onTrashList { _ in TrashList(items: items, total: 500) }
        let whole = try model()
        await whole.load()
        #expect(whole.capNote == nil)
    }

    @Test func restoreRemovesTheRowAndSaysSo() async throws {
        let id = UUID()
        server.onTrashList { _ in TrashList(items: [Self.trashed(id: id), Self.trashed()]) }
        let model = try model()
        await model.load()

        await model.restore(id)

        #expect(server.calls.contains(.restore(Self.url, id)))
        #expect(!model.rows.contains { $0.id == id })
        #expect(model.rows.count == 1)
        #expect(model.notice == "De brief is teruggezet.")
        #expect(events.all == ["restored"])
    }

    @Test func aViewerCannotRestore() async throws {
        let id = UUID()
        server.onTrashList { _ in TrashList(items: [Self.trashed(id: id)]) }
        let model = try model(canRestore: false)
        await model.load()

        await model.restore(id)

        #expect(!server.calls.contains { if case .restore = $0 { true } else { false } })
        #expect(model.rows.count == 1)
    }

    @Test func rowsCarryTheirRestoreLabelForVoiceOver() async throws {
        server.onTrashList { _ in TrashList(items: [Self.trashed(sender: "CAK")]) }
        let model = try model()

        await model.load()

        #expect(model.rows.first?.restoreLabel == "Terugzetten: CAK")
    }

    @Test func aFailingRestoreKeepsTheRowAndSaysWhy() async throws {
        let id = UUID()
        server.onTrashList { _ in TrashList(items: [Self.trashed(id: id)]) }
        server.onRestore { _, _ in throw ServerError.other("forbidden") }
        let model = try model()
        await model.load()

        await model.restore(id)

        #expect(model.rows.map(\.id) == [id])
        #expect(model.notice == "Je mag dit niet doen in deze werkruimte.")
        #expect(events.all.isEmpty)
    }

    @Test func theTrashStringsMatchTheCatalog() throws {
        for (key, resolved) in DocumentStrings.trash {
            #expect(try CatalogParity.dutchValue(forKey: key, target: "FeatureDocuments") == resolved, "\(key)")
        }
        let forms = try CatalogParity.dutchPlural(forKey: "trash.daysLeft", target: "FeatureDocuments")
        #expect(forms["one"] == "Nog %lld dag")
        #expect(forms["other"] == "Nog %lld dagen")
    }
}
