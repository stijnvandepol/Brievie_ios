#if os(iOS)
import BrievieCore
import BrievieUI
import SwiftUI

/// The review of one document: the pages on top, then what the server proposes. Every value read from the
/// letter can show where it stands; nothing becomes a task before "Bevestigen".
public struct ReviewView: View {
    @Bindable private var model: ReviewModel
    @State private var source: SourceQuote?
    @Environment(\.scenePhase) private var scenePhase

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
                doneSections
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(DocumentStrings.reviewTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await model.load()
            model.startPolling()
        }
        .onDisappear { model.stopPolling() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                model.startPolling()
            } else {
                // A sheet sits above the lock screen and the app-switcher cover: the letter text must not
                // stay on screen when the app leaves the foreground. No polling while nobody looks either.
                source = nil
                model.stopPolling()
            }
        }
        .sheet(item: $source) { quote in
            SourceView(quote: quote.text, pageTexts: model.pageTexts) { source = nil }
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
                TabView {
                    ForEach(1...model.pageCount, id: \.self) { index in
                        PageImageView(
                            data: model.pages[index],
                            label: String(format: DocumentStrings.pageFormat, index, model.pageCount)
                        )
                        .task { await model.loadPage(index) }
                    }
                }
                .tabViewStyle(.page)
                .indexViewStyle(.page(backgroundDisplayMode: .always))
                .frame(height: 360)
                .listRowInsets(EdgeInsets())
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
            sourceButton(model.draft.senderQuote)
            unverifiedHint("sender")
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
            OptionalDateRow(title: DocumentStrings.letterDate, date: $model.draft.letterDate)
            sourceButton(model.draft.letterDateQuote)
            unverifiedHint("letter_date")
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
            taskSection($task)
        }
        Section {
            Button {
                model.addTask()
            } label: {
                Label(DocumentStrings.addTask, systemImage: "plus")
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

    private func taskSection(_ task: Binding<TaskDraft>) -> some View {
        Section {
            Picker(DocumentStrings.taskType, selection: task.type) {
                ForEach(DocumentTypes.taskTypes, id: \.code) { type in
                    Text(type.label).tag(type.code)
                }
            }
            TextField(DocumentStrings.taskDescription, text: task.description, axis: .vertical)
            OptionalDateRow(
                title: DocumentStrings.deadline,
                date: Binding(
                    get: { task.wrappedValue.deadline },
                    set: { model.setDeadline($0, for: task.wrappedValue.id) }
                )
            )
            if task.wrappedValue.needsAttention {
                Label(DocumentStrings.checkCarefully, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
            sourceButton(task.wrappedValue.deadlineQuote)
            Button(DocumentStrings.removeTask, role: .destructive) {
                model.removeTask(task.wrappedValue.id)
            }
        } header: {
            Text(DocumentStrings.tasks)
        }
    }

    @ViewBuilder
    private func sourceButton(_ quote: String) -> some View {
        if !quote.isEmpty {
            Button {
                source = SourceQuote(text: quote)
            } label: {
                Label(DocumentStrings.whereIsThis, systemImage: "text.magnifyingglass")
            }
        }
    }

    @ViewBuilder
    private func unverifiedHint(_ field: String) -> some View {
        if let value = model.draft.unverified[field] {
            Label(
                String(format: DocumentStrings.unverifiedFormat, value), systemImage: "exclamationmark.triangle.fill"
            )
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
    }

    // MARK: - Done

    @ViewBuilder private var doneSections: some View {
        if let detail = model.detail {
            Section {
                LabeledContent(DocumentStrings.sender, value: detail.summary.sender)
                LabeledContent(
                    DocumentStrings.documentType, value: DocumentTypes.documentTypeLabel(detail.summary.documentType)
                )
                if let date = detail.summary.letterDate {
                    LabeledContent(DocumentStrings.letterDate, value: date.display)
                }
            }
            if !detail.summaryText.isEmpty {
                Section {
                    Text(detail.summaryText)
                } header: {
                    Text(DocumentStrings.summary)
                } footer: {
                    if detail.summaryByAI {
                        Label(DocumentStrings.summaryByAI, systemImage: "sparkles")
                    }
                }
            }
            Section {
                if detail.tasks.isEmpty {
                    Text(DocumentStrings.noTasks)
                        .foregroundStyle(.secondary)
                }
                ForEach(detail.tasks) { task in
                    ConfirmedTaskRow(task: task) { source = SourceQuote(text: task.deadlineQuote) }
                }
            } header: {
                Text(DocumentStrings.tasks)
            }
        }
    }
}

/// The quote whose place in the letter is being shown.
private struct SourceQuote: Identifiable {
    let text: String
    var id: String { text }
}

private struct ConfirmedTaskRow: View {
    let task: ConfirmedTask
    let showSource: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(task.description)
                .font(.headline)
            Text("\(DocumentTypes.taskTypeLabel(task.type)) · \(task.deadline?.display ?? DocumentStrings.noDeadline)")
                .font(.subheadline)
            if task.deadlineQuote.isEmpty {
                if task.deadline != nil {
                    Text(DocumentStrings.manualSource)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text(String(format: DocumentStrings.sourceFormat, task.deadlineQuote))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button(DocumentStrings.whereIsThis, action: showSource)
                    .font(.footnote)
                    .buttonStyle(.borderless)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A date that may be absent: a button to add one, or a picker with a way to remove it.
private struct OptionalDateRow: View {
    let title: String
    @Binding var date: CalendarDate?

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
                Button(DocumentStrings.addDate) { date = CalendarDate(Date(), in: .current) }
            }
        }
    }
}

private struct PageImageView: View {
    let data: Data?
    let label: String

    var body: some View {
        Group {
            if let data, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .accessibilityLabel(label)
            } else if data != nil {
                // Loaded, but not an image this phone can show.
                Label(DocumentStrings.pageUnreadable, systemImage: "photo")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("\(label). \(DocumentStrings.pageUnreadable)")
            } else {
                VStack(spacing: 8) {
                    ProgressView()
                    Text(DocumentStrings.pageLoading)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(label)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, 32)
    }
}
#endif
