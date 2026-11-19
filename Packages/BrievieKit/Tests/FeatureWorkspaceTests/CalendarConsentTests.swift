@testable import BrievieCore
@testable import FeatureWorkspace
import Foundation
import Testing

/// The switch when the only account left for the calendar is someone else's, and when the calendar's account
/// disappears.
@MainActor
@Suite struct CalendarConsentTests {
    private static let exchange = CalendarSource(id: "exchange", title: "Werk", kind: .other)
    private static let local = CalendarSource(id: "local", title: "Op mijn iPhone", kind: .local)

    private let settings = InMemoryCalendarSettings()
    private let workspace = UUID()

    private func makeModel(_ store: FakeCalendarStore) -> CalendarSettingModel {
        let task = WorkspaceTask(
            id: UUID(), type: "pay", description: "Factuur", deadline: CalendarDate(year: 2026, month: 12, day: 1),
            isDone: false, documentID: nil, sender: "Eneco"
        )
        let sync = CalendarSync(
            store: store, settings: settings, tasks: { _ in [task] }, workspaceName: { _ in "Thuis" },
            typeTitle: { $0 }, today: { CalendarDate(year: 2026, month: 11, day: 16) }
        )
        return CalendarSettingModel(
            workspaceID: workspace, workspaceName: "Thuis", sync: sync, settings: settings, openSettings: {}
        )
    }

    @Test func onlyAnotherAccountAsksByItsNameAndMakesNothingYet() async {
        let store = FakeCalendarStore(sources: [Self.exchange], defaultSourceID: Self.exchange.id)
        let model = makeModel(store)

        model.toggle(true)
        await model.pendingTask?.value

        #expect(model.isAskingConsent)
        #expect(model.consentQuestion == """
            Brievie zet je taken in de agenda van Werk. Wie die account beheert, kan ze lezen.
            """)
        #expect(!model.isOn)
        #expect(!settings.isEnabled(for: workspace))
        #expect(await store.calendars.isEmpty)
    }

    @Test func yesMakesTheCalendarInThatAccountAndTheFooterNamesIt() async throws {
        let store = FakeCalendarStore(sources: [Self.exchange], defaultSourceID: Self.exchange.id)
        let model = makeModel(store)
        model.toggle(true)
        await model.pendingTask?.value

        model.answerConsent(true)
        await model.pendingTask?.value

        #expect(model.isOn)
        #expect(!model.isAskingConsent)
        let id = try #require(settings.calendarID(for: workspace))
        #expect(await store.sourceID(ofCalendar: id) == Self.exchange.id)
        #expect(model.footer.hasPrefix(
            "Je taken met een deadline staan in een eigen agenda 'Brievie – Thuis' in de account Werk. "
                + "Wie die account beheert, kan ze lezen."
        ))
    }

    @Test func noLeavesTheSwitchOff() async {
        let store = FakeCalendarStore(sources: [Self.exchange], defaultSourceID: Self.exchange.id)
        let model = makeModel(store)
        model.toggle(true)
        await model.pendingTask?.value

        model.answerConsent(false)
        await model.pendingTask?.value

        #expect(!model.isOn)
        #expect(!settings.isEnabled(for: workspace))
        #expect(await store.calendars.isEmpty)
    }

    @Test func leavingTheForegroundIsANo() async {
        let store = FakeCalendarStore(sources: [Self.exchange], defaultSourceID: Self.exchange.id)
        let model = makeModel(store)
        model.toggle(true)
        await model.pendingTask?.value

        model.sceneLeftForeground()
        await model.pendingTask?.value

        #expect(!model.isAskingConsent)
        #expect(!model.isOn)
        #expect(await store.calendars.isEmpty)
    }

    @Test func iCloudOrThePhoneNeedNoQuestionAndTheFooterSaysWhere() async {
        let store = FakeCalendarStore(sources: [Self.exchange, Self.local], defaultSourceID: Self.exchange.id)
        let model = makeModel(store)

        model.toggle(true)
        await model.pendingTask?.value

        #expect(model.isOn)
        #expect(!model.isAskingConsent)
        #expect(model.footer.hasPrefix(
            "Je taken met een deadline staan in een eigen agenda 'Brievie – Thuis' op deze iPhone."
        ))
    }

    @Test func theFooterOfASwitchThatIsOffPromisesNoOtherAccountWithoutAsking() {
        let model = makeModel(FakeCalendarStore())

        #expect(model.footer.hasPrefix("""
            Je taken met een deadline komen in een eigen agenda 'Brievie – Thuis' in iCloud of op deze iPhone. \
            Een andere account gebruikt Brievie alleen als jij dat goedvindt.
            """))
    }

    @Test func aRefreshThatFindsTheAccountGoneTurnsTheSwitchOffAndSaysSo() async throws {
        let store = FakeCalendarStore(sources: [Self.exchange], defaultSourceID: Self.exchange.id)
        let model = makeModel(store)
        model.toggle(true)
        await model.pendingTask?.value
        model.answerConsent(true)
        await model.pendingTask?.value
        await store.userRemovesSource(id: Self.exchange.id)

        model.refresh()
        await model.refreshTask?.value

        #expect(!model.isOn)
        #expect(model.message == WorkspaceStrings.calendarSourceGone)
        #expect(!settings.isEnabled(for: workspace))
        #expect(await store.calendars.isEmpty)
    }

    @Test func noAccountAtAllSaysSo() async {
        let model = makeModel(FakeCalendarStore(sources: [], defaultSourceID: nil))

        model.toggle(true)
        await model.pendingTask?.value

        #expect(!model.isOn)
        #expect(model.message == WorkspaceStrings.calendarNoCalendarAccount)
    }
}

/// A sync elsewhere (after a confirm or a ticked task) found the calendar's account gone and turned the setting
/// off; the switch in the reused settings must follow on the next refresh.
@MainActor
@Suite struct CalendarSwitchFollowsOtherSyncsTests {
    private static let exchange = CalendarSource(id: "exchange", title: "Werk", kind: .other)

    @Test func aSwitchTurnedOffByAnotherSyncGoesOffWithTheMessage() async {
        let settings = InMemoryCalendarSettings()
        let workspace = UUID()
        let store = FakeCalendarStore(sources: [Self.exchange], defaultSourceID: Self.exchange.id)
        let sync = CalendarSync(
            store: store, settings: settings, tasks: { _ in [] }, workspaceName: { _ in "Thuis" },
            typeTitle: { $0 }, today: { CalendarDate(year: 2026, month: 11, day: 16) }
        )
        let model = CalendarSettingModel(
            workspaceID: workspace, workspaceName: "Thuis", sync: sync, settings: settings, openSettings: {}
        )
        model.toggle(true)
        await model.pendingTask?.value
        model.answerConsent(true)
        await model.pendingTask?.value
        #expect(model.isOn)
        await store.userRemovesSource(id: Self.exchange.id)

        // The sync after a confirm: its result goes nowhere near this switch.
        #expect(await sync.sync(workspace: workspace) == .sourceGone)
        model.refresh()
        await model.refreshTask?.value

        #expect(!model.isOn)
        #expect(model.message == WorkspaceStrings.calendarSourceGone)
    }
}

/// A pull-to-refresh while switching on is still running must not say "account gone": the setting is off only
/// because the switch-on has not stored it (yet, or at all).
@MainActor
@Suite struct CalendarRefreshDuringEnableTests {
    private static let exchange = CalendarSource(id: "exchange", title: "Werk", kind: .other)

    @Test func aRefreshDuringASwitchOnThatNeedsAYesShowsNoAccountGone() async {
        let settings = InMemoryCalendarSettings()
        let workspace = UUID()
        let store = FakeCalendarStore(sources: [Self.exchange], defaultSourceID: Self.exchange.id)
        // The switch-on waits for the open tasks until the refresh is under way.
        let (gate, open) = AsyncStream<Void>.makeStream()
        let sync = CalendarSync(
            store: store, settings: settings,
            tasks: { _ in
                for await _ in gate { break }
                return []
            },
            workspaceName: { _ in "Thuis" }, typeTitle: { $0 },
            today: { CalendarDate(year: 2026, month: 11, day: 16) }
        )
        let model = CalendarSettingModel(
            workspaceID: workspace, workspaceName: "Thuis", sync: sync, settings: settings, openSettings: {}
        )

        model.toggle(true)
        model.refresh()
        // The refresh has asked for access (the switch-on has not: it waits for the tasks first).
        while await store.accessChecks < 1 { await Task.yield() }
        for _ in 0..<10 { await Task.yield() }
        open.yield()
        open.yield()
        await model.pendingTask?.value
        await model.refreshTask?.value

        #expect(model.isAskingConsent)
        #expect(model.message != WorkspaceStrings.calendarSourceGone)
    }
}
