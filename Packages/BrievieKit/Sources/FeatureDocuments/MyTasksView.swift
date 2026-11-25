#if os(iOS)
import BrievieCore
import BrievieUI
import SwiftUI

/// "Mijn taken": the member's tasks by date, in the server's groups, to tick off, pick up, hand over or date.
/// Depends only on `MyTasksModel` and the letter screen it opens, so it can stand in the title menu now and in a
/// "Taken" tab later. It opens a letter itself (its own navigation destination).
public struct MyTasksView<Destination: View>: View {
    private let model: MyTasksModel
    /// The list a letter opened from here reports its trash to: its "Ongedaan maken" stands here too, where the
    /// letter was deleted, not only in that list's tab.
    private let trashList: DocumentsModel?
    private let destination: (UUID) -> Destination
    @State private var openedLetter: LetterLink?
    @Environment(\.scenePhase) private var scenePhase

    public init(
        model: MyTasksModel, trashList: DocumentsModel? = nil, @ViewBuilder destination: @escaping (UUID) -> Destination
    ) {
        self.model = model
        self.trashList = trashList
        self.destination = destination
    }

    public var body: some View {
        @Bindable var model = model
        List {
            if let trashList, let undo = trashList.undo {
                Section {
                    UndoRow(
                        notice: undo, isUndoing: trashList.isUndoing,
                        undo: {
                            Task {
                                await trashList.undoTrash(reopen: false)
                                await model.load()
                            }
                        },
                        close: { trashList.closeUndo() }
                    )
                }
            }
            intro
            pickers
            switch model.state {
            case .loading:
                Section {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text(DocumentStrings.loading)
                    }
                    .accessibilityElement(children: .combine)
                }
            case let .failed(message):
                Section {
                    ErrorBanner(message, actionTitle: DocumentStrings.retry) { Task { await model.load() } }
                }
            case .notSupported:
                Section { ErrorBanner(DocumentStrings.myTasksNotSupported, style: .warning) }
            case .loaded:
                if model.tab == .open { openTasks } else { doneTasks }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(BrievieColor.surface)
        .navigationTitle(DocumentStrings.myTasksTitle)
        .navigationBarTitleDisplayMode(.large)
        .refreshable { await model.load() }
        .task { await model.load() }
        .onDisappear { model.leave() }
        .onChange(of: model.announcement) { _, announcement in
            if let announcement { AccessibilityNotification.Announcement(announcement).post() }
        }
        .onChange(of: model.actionError) { _, error in
            if let error { AccessibilityNotification.Announcement(error).post() }
        }
        // A sheet would sit above the lock screen: it closes when the app leaves the foreground.
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { model.closeSheet() }
        }
        .sheet(item: $model.sheet) { sheet in
            switch sheet {
            case let .handOver(taskID, title, people):
                HandOverSheet(
                    title: title, people: people, emptyText: model.handOverEmptyText, error: model.sheetError,
                    choose: { user in Task { await model.handOver(taskID, to: user) } },
                    cancel: { model.closeSheet() }
                )
            case let .setDate(taskID, title, term, current):
                SetDateSheet(
                    title: title, term: term, current: current, error: model.sheetError,
                    save: { date in Task { await model.setDate(date, for: taskID) } },
                    cancel: { model.closeSheet() }
                )
            }
        }
        .navigationDestination(item: $openedLetter) { link in
            destination(link.documentID)
        }
    }

    // MARK: - Parts

    /// What the screen is for, and what keeps a member from acting or seeing everything.
    @ViewBuilder private var intro: some View {
        Section {
            Text(model.description)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let notice = model.viewerNotice { ErrorBanner(notice, style: .warning) }
            if let notice = model.noPersonNotice { ErrorBanner(notice, style: .warning) }
            if let error = model.actionError { ErrorBanner(error) }
        }
        if let waiting = model.waitingLine {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Label(waiting, systemImage: "tray")
                        .fixedSize(horizontal: false, vertical: true)
                    Button(DocumentStrings.myTasksShowInbox) { model.showInbox() }
                        .buttonStyle(.borderless)
                        .frame(minHeight: 44)
                }
            }
        }
    }

    private var pickers: some View {
        Section {
            Picker(
                DocumentStrings.myTasksTabLabel,
                selection: Binding(get: { model.tab }, set: { tab in Task { await model.select(tab) } })
            ) {
                Text(DocumentStrings.myTasksTabOpen).tag(MyTasksModel.Tab.open)
                Text(DocumentStrings.myTasksTabDone).tag(MyTasksModel.Tab.done)
            }
            Picker(
                DocumentStrings.myTasksFilterLabel,
                selection: Binding(get: { model.filter }, set: { filter in Task { await model.select(filter) } })
            ) {
                Text(DocumentStrings.myTasksFilterMine).tag(MyTasksModel.Filter.mine)
                Text(DocumentStrings.myTasksFilterAll).tag(MyTasksModel.Filter.all)
            }
        }
        .pickerStyle(.segmented)
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
    }

    @ViewBuilder private var openTasks: some View {
        if let empty = model.emptyText {
            Section { emptyText(empty) }
        }
        ForEach(model.sections) { section in
            taskSection(section)
        }
        if let toPickUp = model.toPickUp {
            if let empty = model.toPickUpEmptyText {
                Section {
                    emptyText(empty)
                } header: {
                    sectionHeader(toPickUp.title)
                }
            } else {
                taskSection(toPickUp)
            }
        }
        if let truncated = model.truncatedNote {
            Section { Text(truncated).font(.footnote).foregroundStyle(.secondary) }
        }
    }

    @ViewBuilder private var doneTasks: some View {
        if let empty = model.emptyText {
            Section { emptyText(empty) }
        } else {
            Section {
                ForEach(model.doneRows) { row in taskRow(row) }
            }
        }
    }

    private func taskSection(_ section: MyTasksModel.Section) -> some View {
        Section {
            ForEach(section.rows) { row in taskRow(row) }
        } header: {
            sectionHeader(section.header, isLate: section.group == .overdue)
        }
    }

    private func sectionHeader(_ text: String, isLate: Bool = false) -> some View {
        Text(text)
            .font(.title3.weight(.bold))
            .foregroundStyle(isLate ? BrievieColor.warning : Color.primary)
            .textCase(nil)
            .accessibilityAddTraits(.isHeader)
    }

    private func emptyText(_ text: String) -> some View {
        Text(text)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func taskRow(_ row: MyTasksModel.Row) -> some View {
        MyTaskRowView(
            row: row,
            tick: { done in Task { await model.setDone(done, for: row.id) } },
            actions: MyTaskRowActions(
                takeOn: row.canTakeOn ? { Task { await model.takeOn(row.id) } } : nil,
                release: row.canRelease ? { Task { await model.release(row.id) } } : nil,
                handOver: row.canHandOver ? { Task { await model.startHandOver(row.id) } } : nil,
                setDate: row.canSetDate ? { model.startSettingDate(row.id) } : nil,
                openLetter: row.documentID.map { id in { openedLetter = LetterLink(documentID: id) } }
            ),
            undoLabel: model.tab == .open ? DocumentStrings.myTasksUndo : DocumentStrings.myTasksNotDone
        )
    }
}

/// The letter a task row opens.
struct LetterLink: Identifiable, Hashable {
    let documentID: UUID
    var id: UUID { documentID }
}

#Preview("Thuis") {
    NavigationStack {
        MyTasksView(model: MyTasksPreviews.model()) { _ in EmptyView() }
    }
}

#Preview("Organisatie, groot") {
    NavigationStack {
        MyTasksView(model: MyTasksPreviews.model(split: true)) { _ in EmptyView() }
    }
    .dynamicTypeSize(.accessibility5)
}

#Preview("Kijker, donker") {
    NavigationStack {
        MyTasksView(model: MyTasksPreviews.model(canEdit: false, hasPerson: false)) { _ in EmptyView() }
    }
    .preferredColorScheme(.dark)
}

#Preview("Leeg") {
    NavigationStack {
        MyTasksView(model: MyTasksPreviews.model(tasks: [])) { _ in EmptyView() }
    }
}

/// Models for the previews, on a `FakeDocumentServer`.
@MainActor
enum MyTasksPreviews {
    static func model(
        split: Bool = false, canEdit: Bool = true, hasPerson: Bool = true, tasks: [WorkspaceTask]? = nil
    ) -> MyTasksModel {
        let server = FakeDocumentServer { _, id in DocumentFixtures.detail(id: id) }
        let items = tasks ?? sample
        server.onMyTasks { _, part, _ in
            MyTasks(
                items: part == .toPickUp ? [pickUp] : items, today: CalendarDate(year: 2026, month: 11, day: 21),
                hasPerson: hasPerson, waitingLetters: 2, split: split
            )
        }
        let store = ConnectionStore(secrets: InMemorySecretStore())
        let connection = ServerConnection(
            urls: [URL(fileURLWithPath: "/")], caCertificateDER: nil, deviceID: UUID(), userName: "Lid"
        )
        try? store.save(connection, token: "preview")
        let documents = WorkspaceDocuments(workspaceID: UUID(), connection: connection, store: store, server: server)
        return MyTasksModel(
            documents: documents, canEdit: canEdit, onTasksChanged: {}, onShowInbox: {}, onRevoked: {},
            onMissingPairing: {}
        )
    }

    private nonisolated static let sample: [WorkspaceTask] = [
        WorkspaceTask(
            id: UUID(), type: "pay", description: "Betaal de aanslag",
            deadline: CalendarDate(year: 2026, month: 11, day: 18),
            isDone: false, documentID: UUID(), sender: "Belastingdienst", deadlineSource: "in_document",
            deadlineQuote: "vóór 18 november", amount: TaskAmount.parse(api: "1234.56"), daysLeft: -3, group: .overdue,
            reason: .addressee, canEdit: true
        ),
        WorkspaceTask(
            id: UUID(), type: "respond", description: "Reageer op de brief", deadline: nil, isDone: false,
            documentID: UUID(), sender: "Gemeente", termQuote: "binnen zes weken na dagtekening",
            needsDeadline: true, group: .noDate, reason: .assigned, assignedByName: "Beheerder", canEdit: true
        )
    ]

    private nonisolated static let pickUp = WorkspaceTask(
        id: UUID(), type: "pay", description: "Betaal de factuur",
        deadline: CalendarDate(year: 2026, month: 11, day: 25),
        isDone: false, documentID: UUID(), sender: "KPN", daysLeft: 4, group: .withinWeek, reason: .department,
        forNames: ["Finance"], canEdit: true
    )
}
#endif
