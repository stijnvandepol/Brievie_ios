@testable import BrievieCore
import Foundation
import Testing

/// Where a workspace's calendar may be made. Silently only in iCloud or on the phone itself; another account
/// (an employer's Exchange, Google, any CalDAV server) only after the user said yes to that account, and a
/// calendar is never made again in an account the user did not agree to.
@Suite struct CalendarSourceTests {
    private static let today = CalendarDate(year: 2026, month: 11, day: 17)
    private static let iCloud = CalendarSource(id: "icloud", title: "iCloud", kind: .iCloud)
    private static let local = CalendarSource(id: "local", title: "Op mijn iPhone", kind: .local)
    private static let exchange = CalendarSource(id: "exchange", title: "Werk", kind: .other)
    private static let google = CalendarSource(id: "google", title: "Gmail", kind: .other)

    private let settings = InMemoryCalendarSettings()
    private let home = UUID()

    private func makeSync(_ store: FakeCalendarStore) -> CalendarSync {
        let task = WorkspaceTask(
            id: UUID(), type: "pay", description: "Factuur", deadline: Self.today, isDone: false, documentID: nil,
            sender: "Eneco"
        )
        return CalendarSync(
            store: store, settings: settings, tasks: { _ in [task] }, workspaceName: { _ in "Thuis" },
            typeTitle: { $0 }, today: { Self.today }
        )
    }

    // MARK: - The choice

    @Test func iCloudAsTheDefaultIsChosenSilently() {
        let choice = CalendarSourceChoice(sources: [Self.iCloud, Self.local], defaultSourceID: Self.iCloud.id)

        #expect(choice == .silent(Self.iCloud))
    }

    @Test func aDefaultInAnotherAccountIsPassedOverForICloud() {
        let choice = CalendarSourceChoice(sources: [Self.exchange, Self.iCloud], defaultSourceID: Self.exchange.id)

        #expect(choice == .silent(Self.iCloud))
    }

    @Test func aDefaultInAnotherAccountIsPassedOverForThePhone() {
        let choice = CalendarSourceChoice(sources: [Self.exchange, Self.local], defaultSourceID: Self.exchange.id)

        #expect(choice == .silent(Self.local))
    }

    @Test func onlyAnotherAccountNeedsTheUsersYes() {
        #expect(
            CalendarSourceChoice(sources: [Self.google, Self.exchange], defaultSourceID: Self.exchange.id)
                == .needsConsent(Self.exchange)
        )
        #expect(CalendarSourceChoice(sources: [Self.google], defaultSourceID: nil) == .needsConsent(Self.google))
    }

    @Test func noAccountAtAllIsNone() {
        #expect(CalendarSourceChoice(sources: [], defaultSourceID: nil) == .none)
    }

    // MARK: - Switching on

    @Test func switchingOnWithAnExchangeDefaultMakesTheCalendarInICloud() async throws {
        let store = FakeCalendarStore(sources: [Self.exchange, Self.iCloud], defaultSourceID: Self.exchange.id)

        let result = await makeSync(store).enable(workspace: home)

        #expect(result == .done(created: 1, updated: 0, deleted: 0))
        let id = try #require(settings.calendarID(for: home))
        #expect(await store.sourceID(ofCalendar: id) == Self.iCloud.id)
        #expect(settings.sourceID(for: home) == Self.iCloud.id)
    }

    @Test func onlyAnotherAccountAsksAndMakesNothing() async {
        let store = FakeCalendarStore(sources: [Self.exchange], defaultSourceID: Self.exchange.id)

        let result = await makeSync(store).enable(workspace: home)

        #expect(result == .needsConsent(Self.exchange))
        #expect(!settings.isEnabled(for: home))
        #expect(await store.calendars.isEmpty)
    }

    @Test func afterTheUsersYesTheCalendarIsMadeInThatAccount() async throws {
        let store = FakeCalendarStore(sources: [Self.exchange], defaultSourceID: Self.exchange.id)

        let result = await makeSync(store).enable(workspace: home, consentedSourceID: Self.exchange.id)

        #expect(result == .done(created: 1, updated: 0, deleted: 0))
        let id = try #require(settings.calendarID(for: home))
        #expect(await store.sourceID(ofCalendar: id) == Self.exchange.id)
        #expect(settings.sourceID(for: home) == Self.exchange.id)
    }

    @Test func aYesForOneAccountIsNoYesForAnother() async {
        let store = FakeCalendarStore(sources: [Self.google], defaultSourceID: Self.google.id)

        let result = await makeSync(store).enable(workspace: home, consentedSourceID: Self.exchange.id)

        #expect(result == .needsConsent(Self.google))
        #expect(await store.calendars.isEmpty)
    }

    @Test func noAccountAtAllSaysSo() async {
        let store = FakeCalendarStore(sources: [], defaultSourceID: nil)

        #expect(await makeSync(store).enable(workspace: home) == .noCalendarAccount)
        #expect(!settings.isEnabled(for: home))
    }

    @Test func aCalendarWithTheSameTitleInAnotherAccountIsNotAdopted() async throws {
        let store = FakeCalendarStore(sources: [Self.exchange, Self.iCloud], defaultSourceID: Self.exchange.id)
        let atWork = await store.userAddsCalendar(title: "Brievie – Thuis", sourceID: Self.exchange.id)

        _ = await makeSync(store).enable(workspace: home)

        let id = try #require(settings.calendarID(for: home))
        #expect(id != atWork)
        #expect(await store.sourceID(ofCalendar: id) == Self.iCloud.id)
    }

    // MARK: - Making it again

    @Test func aDeletedCalendarIsMadeAgainInTheAgreedAccountWhateverTheDefaultIsNow() async throws {
        let store = FakeCalendarStore(sources: [Self.exchange], defaultSourceID: Self.exchange.id)
        let sync = makeSync(store)
        _ = await sync.enable(workspace: home, consentedSourceID: Self.exchange.id)
        await store.userDeletesCalendar(id: try #require(settings.calendarID(for: home)))
        await store.setSources([Self.exchange, Self.google], defaultSourceID: Self.google.id)

        #expect(await sync.sync(workspace: home) == .done(created: 1, updated: 0, deleted: 0))

        let id = try #require(settings.calendarID(for: home))
        #expect(await store.sourceID(ofCalendar: id) == Self.exchange.id)
    }

    @Test func whenTheAgreedAccountIsGoneTheSwitchGoesOffAndNothingIsMadeElsewhere() async throws {
        let store = FakeCalendarStore(sources: [Self.exchange], defaultSourceID: Self.exchange.id)
        let sync = makeSync(store)
        _ = await sync.enable(workspace: home, consentedSourceID: Self.exchange.id)
        // The employer's account was removed from the phone; its calendars went with it.
        await store.userRemovesSource(id: Self.exchange.id)
        await store.setSources([Self.google, Self.iCloud], defaultSourceID: Self.google.id)

        #expect(await sync.sync(workspace: home) == .sourceGone)

        #expect(!settings.isEnabled(for: home))
        #expect(await store.calendars.isEmpty)
    }

    @Test func anICloudCalendarIsNotMadeAgainOnThePhoneWithoutTheUser() async throws {
        let store = FakeCalendarStore(sources: [Self.iCloud, Self.local], defaultSourceID: Self.iCloud.id)
        let sync = makeSync(store)
        _ = await sync.enable(workspace: home)
        await store.userRemovesSource(id: Self.iCloud.id)

        #expect(await sync.sync(workspace: home) == .sourceGone)
        #expect(await store.calendars.isEmpty)
    }

    @Test func aSettingFromBeforeTheSourceWasStoredLearnsItsSource() async throws {
        let store = FakeCalendarStore(sources: [Self.exchange], defaultSourceID: Self.exchange.id)
        let earlier = await store.userAddsCalendar(title: "Brievie – Thuis", sourceID: Self.exchange.id)
        settings.enable(workspace: home, calendarID: earlier)

        #expect(await makeSync(store).sync(workspace: home) == .done(created: 1, updated: 0, deleted: 0))
        #expect(settings.sourceID(for: home) == Self.exchange.id)
    }

    @Test func aSettingFromBeforeWhoseCalendarIsGoneIsNotMadeAgainInAnotherAccount() async {
        let store = FakeCalendarStore(sources: [Self.exchange], defaultSourceID: Self.exchange.id)
        settings.enable(workspace: home, calendarID: "gone")

        #expect(await makeSync(store).sync(workspace: home) == .sourceGone)
        #expect(!settings.isEnabled(for: home))
        #expect(await store.calendars.isEmpty)
    }

    @Test func aSettingFromBeforeWhoseCalendarIsGoneIsMadeAgainInICloud() async throws {
        let store = FakeCalendarStore(sources: [Self.exchange, Self.iCloud], defaultSourceID: Self.exchange.id)
        settings.enable(workspace: home, calendarID: "gone")

        #expect(await makeSync(store).sync(workspace: home) == .done(created: 1, updated: 0, deleted: 0))
        let id = try #require(settings.calendarID(for: home))
        #expect(await store.sourceID(ofCalendar: id) == Self.iCloud.id)
    }

    @Test func theDestinationNamesTheAccount() async throws {
        let store = FakeCalendarStore(sources: [Self.exchange], defaultSourceID: Self.exchange.id)
        let sync = makeSync(store)
        #expect(await sync.destination(workspace: home) == nil)

        _ = await sync.enable(workspace: home, consentedSourceID: Self.exchange.id)

        #expect(await sync.destination(workspace: home) == Self.exchange)
    }

    @Test func theUserDefaultsSettingsKeepTheSourceAndForgetItWithTheRest() {
        let settings = UserDefaultsCalendarSettings(suiteName: "calendar-source-\(UUID().uuidString)")
        let workspace = UUID()

        settings.enable(workspace: workspace, calendarID: "a", sourceID: "icloud")
        #expect(settings.sourceID(for: workspace) == "icloud")
        #expect(settings.calendarIDs() == [workspace: "a"])

        settings.removeAll()
        #expect(settings.sourceID(for: workspace) == nil)
    }
}
