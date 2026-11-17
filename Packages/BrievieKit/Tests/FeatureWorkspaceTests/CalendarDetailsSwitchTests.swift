@testable import BrievieCore
@testable import FeatureWorkspace
import Foundation
import Testing

/// "Toon de omschrijving in de agenda": off by default, per workspace; turning it on or off rewrites the events.
@MainActor
@Suite struct CalendarDetailsSwitchTests {
    private let store = FakeCalendarStore()
    private let settings = InMemoryCalendarSettings()
    private let workspace = UUID()

    private func makeModel() -> CalendarSettingModel {
        let task = WorkspaceTask(
            id: UUID(), type: "pay", description: "Factuur", deadline: CalendarDate(year: 2026, month: 12, day: 1),
            isDone: false, documentID: nil, sender: "Eneco"
        )
        let sync = CalendarSync(
            store: store, settings: settings, tasks: { _ in [task] }, workspaceName: { _ in "Thuis" },
            typeTitle: { _ in "Betalen" }, today: { CalendarDate(year: 2026, month: 11, day: 16) }
        )
        return CalendarSettingModel(
            workspaceID: workspace, workspaceName: "Thuis", sync: sync, settings: settings, openSettings: {}
        )
    }

    private func titles() async throws -> [String] {
        await store.storedEvents(calendarID: try #require(settings.calendarID(for: workspace))).map(\.title)
    }

    @Test func isOffByDefaultAndTheFooterSaysTheLockScreenShowsOnlyTheType() async {
        let model = makeModel()
        model.toggle(true)
        await model.pendingTask?.value

        #expect(!model.showsDetails)
        #expect(model.footer.hasSuffix(
            "In de agenda en bij meldingen op het toegangsscherm staat alleen de soort taak, zoals 'Betalen (Brievie)'."
        ))
    }

    @Test func turningItOnRewritesTheEventsAndTheFooterWarns() async throws {
        let model = makeModel()
        model.toggle(true)
        await model.pendingTask?.value

        model.setShowsDetails(true)
        await model.pendingTask?.value

        #expect(model.showsDetails)
        #expect(settings.showsDetails(for: workspace))
        #expect(try await titles() == ["Betalen: Factuur"])
        #expect(model.footer.hasSuffix(
            "De omschrijving en de afzender staan in de agenda. Ook op het toegangsscherm zijn ze te lezen."
        ))

        model.setShowsDetails(false)
        await model.pendingTask?.value

        #expect(try await titles() == ["Betalen (Brievie)"])
    }

    @Test func theChoiceIsPerWorkspaceAndReadBack() {
        settings.setShowsDetails(true, for: workspace)

        #expect(makeModel().showsDetails)
        #expect(!settings.showsDetails(for: UUID()))
    }

    @Test func itsFooterSaysWhoCanReadTheText() {
        #expect(WorkspaceStrings.calendarDetailsFooter == """
            Dan staan de omschrijving en de afzender in de agenda. Die tekst is dan te lezen op het toegangsscherm \
            en door andere apps die je agenda mogen lezen.
            """)
    }
}
