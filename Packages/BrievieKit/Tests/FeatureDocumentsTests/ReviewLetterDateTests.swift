import BrievieCore
@testable import FeatureDocuments
import Foundation
import Synchronization
import Testing

/// An empty letter date starts as today: a starting value in the draft, never presented as read from the letter.
@MainActor
@Suite struct ReviewLetterDateTests {
    private let harness = ReviewHarness()
    private nonisolated static let amsterdam = TimeZone(identifier: "Europe/Amsterdam") ?? .gmt

    private static func clock(_ iso: String, in timeZone: TimeZone = amsterdam) -> TodayClock {
        let instant = ISO8601DateFormatter().date(from: iso) ?? Date(timeIntervalSince1970: 0)
        return TodayClock(now: { instant }, timeZone: { timeZone })
    }

    private func load(
        _ proposals: [Proposal], stored: CalendarDate? = nil, clock: TodayClock = clock("2026-11-19T09:00:00Z")
    ) async throws -> ReviewModel {
        harness.answer { id in
            let base = DocumentFixtures.detail(id: id, proposals: proposals)
            let summary = base.summary
            return DocumentDetail(
                summary: DocumentSummary(
                    id: summary.id, clientID: summary.clientID, status: summary.status, pageCount: summary.pageCount,
                    createdAt: summary.createdAt, sender: summary.sender, documentType: summary.documentType,
                    letterDate: stored, inboxState: summary.inboxState
                ),
                failureCode: base.failureCode, summaryText: base.summaryText, summaryByAI: base.summaryByAI,
                pageTexts: base.pageTexts, proposals: base.proposals, tasks: base.tasks
            )
        }
        let model = try harness.model(clock: clock)
        await model.load()
        return model
    }

    private var sentReviews: [ConfirmedReview] {
        harness.server.calls.compactMap { call -> ConfirmedReview? in
            if case let .confirm(_, _, review) = call { return review }
            return nil
        }
    }

    @Test func emptyLetterDateStartsAsTodayWithItsOwnOrigin() async throws {
        let model = try await load([DocumentFixtures.proposal("sender", "CAK", quote: "CAK")])

        #expect(model.draft.letterDate == CalendarDate(year: 2026, month: 11, day: 19))
        #expect(model.draft.isToday(.letterDate))
        #expect(model.draft.letterDateQuote.isEmpty)
        #expect(!model.draft.needsAttention(.letterDate))
        #expect(!model.draft.isUnchecked(.letterDate))
        #expect(model.draft.unverified[.letterDate] == nil)
        #expect(!model.draftHasUserEdits)
    }

    @Test func aDraftStartedByHandAlsoStartsWithToday() async throws {
        let model = try await load([])

        #expect(model.draft.letterDate == CalendarDate(year: 2026, month: 11, day: 19))
        #expect(!model.draft.isFromAI)
    }

    @Test func proposedDateWins() async throws {
        let model = try await load([
            DocumentFixtures.proposal("letter_date", "2026-11-03", quote: "3 november")
        ], stored: CalendarDate(year: 2026, month: 10, day: 1))

        #expect(model.draft.letterDate == CalendarDate(year: 2026, month: 11, day: 3))
        #expect(!model.draft.isToday(.letterDate))
        #expect(model.draft.letterDateQuote == "3 november")
    }

    @Test func storedDateWinsOverToday() async throws {
        let model = try await load([], stored: CalendarDate(year: 2026, month: 10, day: 1))

        #expect(model.draft.letterDate == CalendarDate(year: 2026, month: 10, day: 1))
        #expect(!model.draft.isToday(.letterDate))
        #expect(model.draft.letterDateQuote.isEmpty)
    }

    /// A proposal the letter did not support stays a hint; today would put a second, different date beside it.
    @Test func unverifiedProposalLeavesTheDateEmpty() async throws {
        let model = try await load([
            DocumentFixtures.proposal("letter_date", "2026-11-03", confidence: "0")
        ])

        #expect(model.draft.letterDate == nil)
        #expect(model.draft.unverified[.letterDate] != nil)
    }

    @Test(arguments: [
        ("2026-11-19T22:59:59Z", CalendarDate(year: 2026, month: 11, day: 19)),
        ("2026-11-19T23:00:00Z", CalendarDate(year: 2026, month: 11, day: 20)),
        ("2026-06-30T21:59:59Z", CalendarDate(year: 2026, month: 6, day: 30)),
        ("2026-06-30T22:00:00Z", CalendarDate(year: 2026, month: 7, day: 1))
    ])
    func todayIsTheDayInTheUsersTimeZoneAroundMidnight(instant: String, day: CalendarDate) async throws {
        let model = try await load([], clock: Self.clock(instant))

        #expect(model.draft.letterDate == day)
    }

    @Test func theSameInstantIsAnotherDayInAnotherTimeZone() async throws {
        let utc = TimeZone(identifier: "UTC") ?? .gmt
        let model = try await load([], clock: Self.clock("2026-11-19T23:30:00Z", in: utc))

        #expect(model.draft.letterDate == CalendarDate(year: 2026, month: 11, day: 19))
    }

    @Test func confirmingWithoutTouchingSendsToday() async throws {
        let model = try await load([])
        harness.server.onConfirm { _, id, _ in DocumentFixtures.detail(id: id, status: .done) }

        await model.confirm()

        #expect(sentReviews.first?.letterDate == CalendarDate(year: 2026, month: 11, day: 19))
    }

    @Test func theUserCanClearOrChangeIt() async throws {
        let model = try await load([])

        model.draft.letterDate = CalendarDate(year: 2026, month: 11, day: 2)
        #expect(!model.draft.isToday(.letterDate))
        #expect(model.draftHasUserEdits)

        model.draft.letterDate = nil
        #expect(!model.draft.isToday(.letterDate))
        harness.server.onConfirm { _, id, _ in DocumentFixtures.detail(id: id, status: .done) }
        await model.confirm()
        #expect(sentReviews.count == 1)
        #expect(sentReviews.first?.letterDate == nil)
    }

    /// A poll after midnight does not move the date under the user's hands.
    @Test func aRefreshKeepsTheDateTheDraftStartedWith() async throws {
        let instant = LockedInstant(Date(timeIntervalSince1970: 1_795_126_800)) // 23:20 in Amsterdam
        let clock = TodayClock(now: { instant.value }, timeZone: { Self.amsterdam })
        let model = try await load([], clock: clock)
        #expect(model.draft.letterDate == CalendarDate(year: 2026, month: 11, day: 19))

        instant.value = Date(timeIntervalSince1970: 1_795_130_400) // 00:20 the next day
        await model.load()

        #expect(model.draft.letterDate == CalendarDate(year: 2026, month: 11, day: 19))
    }
}

/// A clock a test can move.
final class LockedInstant: Sendable {
    private let mutex: Mutex<Date>

    init(_ instant: Date) { mutex = Mutex(instant) }

    var value: Date {
        get { mutex.withLock { $0 } }
        set { mutex.withLock { $0 = newValue } }
    }
}
