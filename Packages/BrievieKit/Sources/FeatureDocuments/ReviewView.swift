#if os(iOS)
import BrievieCore
import BrievieUI
import SwiftUI

/// The review of one document: the pages on top, then what the server proposes. Every value read from the
/// letter can show where it stands; nothing becomes a task before "Bevestigen".
public struct ReviewView: View {
    @Bindable private var model: ReviewModel
    @Environment(\.scenePhase) private var scenePhase
    /// The page the small page view shows, where "Brief lezen" opens the reader.
    @State private var shownPage = 1

    public init(model: ReviewModel) {
        self.model = model
    }

    public var body: some View {
        List {
            switch model.state {
            case .loading:
                Section { progressRow(DocumentStrings.reviewLoading) }
            case let .failed(message):
                Section {
                    ErrorBanner(message, actionTitle: DocumentStrings.retry) { Task { await model.load() } }
                }
            case .processing:
                pagesSection
                Section { progressRow(DocumentStrings.processingNote) }
            case .review:
                pagesSection
                reviewSections
            case .done:
                pagesSection
                if let detail = model.detail {
                    DoneSections(
                        detail: detail, confirmed: model.confirmed, onPick: { model.pick($0) },
                        onShowQuote: { model.showQuote($0) }
                    )
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(model.title)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await model.load()
            model.startPolling()
        }
        .onDisappear { model.stopPolling() }
        // Closes every sheet when the app leaves the foreground (they would sit above the lock screen).
        .onChange(of: scenePhase) { _, phase in model.sceneDidChange(isActive: phase == .active) }
        // Pushed rather than a sheet or full-screen cover: it stays under the lock screen and needs no closing
        // when the app leaves the foreground.
        .navigationDestination(isPresented: Binding(
            get: { model.reader != nil },
            set: { if !$0 { model.closeReader() } }
        )) {
            if let reader = model.reader {
                LetterReaderView(review: model, reader: reader)
            }
        }
        .sheet(item: $model.shownQuote) { quote in
            SourceView(quote: quote.text, pageTexts: model.pageTexts, missingPagesNote: model.missingPagesNote) {
                model.shownQuote = nil
            }
        }
        .sheet(item: $model.picker) { picker in
            if let confirmed = model.confirmed {
                ConfirmedPicker(model: confirmed, picker: picker) { model.picker = nil }
            } else {
                switch picker {
                case .persons:
                    PersonPickerView(
                        persons: model.persons, selection: $model.draft.organise.addresseeIDs,
                        error: model.personError, onCreate: { await model.createPerson(named: $0) },
                        close: { model.picker = nil }
                    )
                case .labels:
                    LabelPickerView(labels: model.labels, selection: $model.draft.organise.labelIDs) {
                        model.picker = nil
                    }
                }
            }
        }
        .modifier(RemoveTaskQuestion(model: model))
        .confirmationDialog(
            DocumentStrings.discardEditsTitle,
            isPresented: Binding(
                get: { model.confirmsDiscardingEdits },
                set: { if !$0 { model.keepEdits() } }
            ),
            titleVisibility: .visible
        ) {
            Button(DocumentStrings.discardEdits, role: .destructive) {
                Task { await model.retryProcessing(discardingEdits: true) }
            }
            Button(DocumentStrings.keepEdits, role: .cancel) { model.keepEdits() }
        } message: {
            Text(DocumentStrings.discardEditsMessage)
        }
    }

    private func progressRow(_ text: String) -> some View {
        HStack(spacing: 12) {
            ProgressView()
            Text(text)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Pages

    @ViewBuilder private var pagesSection: some View {
        if model.pageCount > 0 {
            Section {
                if let note = model.missingPagesNote {
                    ErrorBanner(note, style: .warning)
                }
                TabView(selection: $shownPage) {
                    ForEach(1...model.pageCount, id: \.self) { index in
                        Button {
                            model.openReader(at: index)
                        } label: {
                            PageImageView(
                                data: model.pages[index],
                                label: String(format: DocumentStrings.pageFormat, index, model.pageCount)
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint(DocumentStrings.readerOpenHint)
                        .tag(index)
                        .task { await model.loadPage(index) }
                    }
                }
                .tabViewStyle(.page)
                .indexViewStyle(.page(backgroundDisplayMode: .always))
                .frame(height: 360)
                .listRowInsets(EdgeInsets())
                Button {
                    model.openReader(at: shownPage)
                } label: {
                    Label(DocumentStrings.readerOpen, systemImage: "arrow.up.left.and.arrow.down.right")
                }
                .accessibilityHint(DocumentStrings.readerOpenHint)
            }
        }
    }

    // MARK: - Review

    @ViewBuilder private var reviewSections: some View {
        if model.processingFailed {
            Section {
                ErrorBanner(
                    DocumentStrings.processingFailedNote, style: .warning,
                    actionTitle: model.canEdit ? DocumentStrings.retryProcessing : nil
                ) { Task { await model.retryProcessing() } }
            }
        }
        if model.draft.isFromAI {
            Section {
                Label(DocumentStrings.aiProposalsNote, systemImage: "sparkles")
                    .font(.subheadline)
            }
        }
        Section {
            TextField(DocumentStrings.sender, text: $model.draft.sender)
            notes(for: .sender, title: DocumentStrings.sender)
        } header: {
            Text(DocumentStrings.sender)
        }
        Section {
            Picker(DocumentStrings.documentType, selection: $model.draft.documentType) {
                Text(DocumentStrings.typeNone).tag("")
                ForEach(DocumentTypes.documentTypes, id: \.code) { type in
                    Text(type.label).tag(type.code)
                }
            }
            notes(for: .documentType, title: DocumentStrings.documentType)
            OptionalDateRow(title: DocumentStrings.letterDate, date: $model.draft.letterDate, today: model.today)
            notes(for: .letterDate, title: DocumentStrings.letterDate)
        }
        if model.organiseAvailable {
            OrganiseSection(
                draft: model.draft.organise, persons: model.persons, labels: model.labels,
                actions: model.canEdit ? .review(
                    $model.draft.organise, pickPersons: { model.pick(.persons) }, pickLabels: { model.pick(.labels) }
                ) : nil,
                onShowQuote: { model.showQuote($0) }
            )
        }
        Section {
            TextField(DocumentStrings.summary, text: $model.draft.summary, axis: .vertical)
                .lineLimit(2...8)
        } header: {
            Text(DocumentStrings.summary)
        } footer: {
            if model.draft.summaryIsByAI {
                Label(DocumentStrings.summaryByAI, systemImage: "sparkles")
            }
        }
        ForEach($model.draft.tasks) { $task in
            taskSection($task, showsHeader: task.id == model.draft.tasks.first?.id)
        }
        Section {
            Button {
                model.addTask()
            } label: {
                Label(DocumentStrings.addTask, systemImage: "plus")
            }
        } header: {
            if model.draft.tasks.isEmpty {
                Text(DocumentStrings.tasks)
            }
        }
        Section {
            if let error = model.saveError {
                ErrorBanner(error)
            }
            if model.canEdit {
                PrimaryButton(model.isSaving ? DocumentStrings.saving : DocumentStrings.confirm) {
                    Task { await model.confirm() }
                }
                .disabled(model.isSaving)
            } else {
                Text(DocumentStrings.readOnly)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// One section per task; the "Wat moet je doen" header only above the first.
    private func taskSection(_ task: Binding<TaskDraft>, showsHeader: Bool) -> some View {
        let id = task.wrappedValue.id
        return Section {
            Picker(DocumentStrings.taskType, selection: task.type) {
                ForEach(DocumentTypes.taskTypes, id: \.code) { type in
                    Text(type.label).tag(type.code)
                }
            }
            notes(for: .taskType(id), title: DocumentStrings.taskType)
            TextField(DocumentStrings.taskDescription, text: task.description, axis: .vertical)
            notes(for: .taskDescription(id), title: DocumentStrings.taskDescription)
            DeadlineRow(model: model, taskID: id, deadline: task.wrappedValue.deadline)
            notes(for: .taskDeadline(id), title: DocumentStrings.deadline)
        } header: {
            if showsHeader {
                Text(DocumentStrings.tasks)
            }
        } footer: {
            // Small and apart from the fields, so a tap while scrolling does not land on it; it asks first.
            HStack {
                Spacer()
                Button(DocumentStrings.removeTask, systemImage: "trash", role: .destructive) {
                    model.requestRemoveTask(id)
                }
                .font(.footnote)
                .buttonStyle(.borderless)
            }
        }
    }

    private func notes(for field: ReviewField, title: String) -> some View {
        FieldNotes(draft: model.draft, field: field, title: title) { model.showQuote($0) }
    }
}

/// What the user needs to judge a pre-filled value: a mark when it needs a second look (or was not read from
/// the letter at all), where it stands in the letter, and a proposal that was not pre-filled. Nothing once the
/// user changed the value: it is theirs.
private struct FieldNotes: View {
    let draft: ReviewModel.Draft
    let field: ReviewField
    /// The field's name, so VoiceOver says which value a mark belongs to.
    let title: String
    let showSource: (String) -> Void

    var body: some View {
        if draft.isUnchecked(field) {
            mark(DocumentStrings.unchecked, systemImage: "questionmark.circle.fill")
        } else if draft.needsAttention(field) {
            mark(DocumentStrings.checkCarefully, systemImage: "exclamationmark.triangle.fill")
        }
        if draft.isToday(field) {
            Label(DocumentStrings.letterDateToday, systemImage: "calendar")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .accessibilityLabel("\(title). \(DocumentStrings.letterDateToday)")
        }
        let quote = draft.quote(for: field)
        if !quote.isEmpty {
            Button {
                showSource(quote)
            } label: {
                Label(DocumentStrings.whereIsThis, systemImage: "text.magnifyingglass")
            }
            .accessibilityLabel("\(title). \(DocumentStrings.whereIsThis)")
        }
        if let value = draft.unverified[field] {
            Label(
                String(format: DocumentStrings.unverifiedFormat, value), systemImage: "exclamationmark.triangle.fill"
            )
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
    }

    private func mark(_ text: String, systemImage: String) -> some View {
        Label(text, systemImage: systemImage)
            .font(.footnote)
            .foregroundStyle(.orange)
            .accessibilityLabel("\(title). \(text)")
    }
}

/// A date that may be absent: a button to add one, or a picker with a way to remove it. Adding fills in `today`
/// at once: right for the letter date, which starts as today anyway (owner decision 2026-11-19).
private struct OptionalDateRow: View {
    let title: String
    @Binding var date: CalendarDate?
    let today: CalendarDate

    var body: some View {
        if let current = date {
            DatePicker(
                title,
                selection: Binding(
                    get: { current.date(in: .current) },
                    set: { date = CalendarDate($0, in: .current) }
                ),
                displayedComponents: .date
            )
            Button(DocumentStrings.removeDate, role: .destructive) { date = nil }
                .font(.footnote)
        } else {
            LabeledContent(title) {
                Button(DocumentStrings.addDate) { date = today }
            }
        }
    }
}
#endif
