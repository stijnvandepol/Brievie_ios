#if os(iOS)
import BrievieCore
import BrievieUI
import SwiftUI

/// "Mogelijk dubbel": the first page and the facts of two letters side by side (one under the other at the
/// accessibility text sizes), what differs marked, and for a member or admin the choice of the letter to keep with
/// "Het is dezelfde brief" and "Het zijn twee brieven". Closes itself once a choice is made.
public struct DuplicateView: View {
    @Bindable private var model: DuplicateModel
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismiss) private var dismiss

    public init(model: DuplicateModel) {
        self.model = model
    }

    public var body: some View {
        List {
            switch model.state {
            case .loading:
                Section {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text(DocumentStrings.loading)
                    }
                    .accessibilityElement(children: .combine)
                }
            case let .gone(message):
                Section { ErrorBanner(message, style: .warning) }
            case let .failed(message):
                Section {
                    ErrorBanner(message, actionTitle: DocumentStrings.retry) { Task { await model.load() } }
                }
            case .loaded:
                loadedSections
            case .finished:
                EmptyView()
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(DocumentStrings.duplicateTitle)
        .navigationBarTitleDisplayMode(.inline)
        // Once: coming back from the reader does not load the pair and both letters again.
        .task { if model.pair == nil { await model.load() } }
        .refreshable { await model.load() }
        .onChange(of: model.state) { _, state in
            if state == .finished { dismiss() }
        }
        // The merge question is a sheet: it closes when the app leaves the foreground.
        .onChange(of: scenePhase) { _, phase in model.sceneDidChange(isActive: phase == .active) }
        .sheet(isPresented: $model.asksToMerge) {
            MergeQuestion(model: model)
        }
        // Pushed, as from the review: it stays under the lock screen.
        .navigationDestination(isPresented: Binding(
            get: { model.reader != nil },
            set: { if !$0 { model.closeReader() } }
        )) {
            if let letter = model.reader {
                LetterReaderView(review: letter, reader: letter.reader)
            }
        }
    }

    @ViewBuilder private var loadedSections: some View {
        Section {
            Text(DocumentStrings.duplicateDescription)
                .fixedSize(horizontal: false, vertical: true)
            if let similarity = model.similarityLine {
                Text(similarity)
                    .foregroundStyle(.secondary)
            }
        }
        Section {
            AdaptiveStack(spacing: 16) {
                ForEach(model.letters) { letter in
                    LetterColumn(
                        letter: letter, page: model.firstPages[letter.id], lettersLoaded: model.lettersLoaded
                    ) {
                        model.openReader(letter.id)
                    }
                }
            }
            .padding(.vertical, 4)
        }
        Section {
            ForEach(model.rows) { row in
                CompareRowView(row: row, letterTitles: model.letters.map(\.title))
            }
        }
        if model.canDecide {
            choiceSections
        }
    }

    @ViewBuilder private var choiceSections: some View {
        Section {
            Picker(DocumentStrings.duplicateKeepQuestion, selection: $model.keepID) {
                ForEach(model.letters) { letter in
                    Text(letter.title)
                        .tag(letter.id)
                        .accessibilityLabel(letter.keepLabel)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } header: {
            Text(DocumentStrings.duplicateKeepQuestion)
                .textCase(nil)
        }
        Section {
            if let note = model.blockedNote {
                ErrorBanner(note, style: .warning)
            }
            if let message = model.message {
                ErrorBanner(message)
            }
            if model.canMerge {
                PrimaryButton(DocumentStrings.duplicateSameLetter) { model.askToMerge() }
            }
            SecondaryButton(DocumentStrings.duplicateTwoLetters) { Task { await model.dismiss() } }
            if model.isSaving {
                ProgressView()
                    .frame(maxWidth: .infinity)
            }
        }
        .disabled(model.isSaving)
    }
}

/// One letter's head and first page: "Brief 1", when it was scanned, and the page, which opens the reader.
private struct LetterColumn: View {
    let letter: DuplicateModel.Letter
    let page: Data?
    /// The pages were asked for: a missing one failed, so it is no longer shown as loading.
    let lettersLoaded: Bool
    let open: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(letter.title)
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Text(letter.scanned)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .fixedSize(horizontal: false, vertical: true)
            Button(action: open) {
                // An empty value shows "cannot be shown" instead of a spinner that never ends.
                PageImageView(data: page ?? (lettersLoaded ? Data() : nil), label: letter.pageLabel)
                    .frame(maxWidth: .infinity, minHeight: 160, maxHeight: 260)
            }
            .buttonStyle(.plain)
            .accessibilityHint(DocumentStrings.readerOpenHint)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

/// One fact of both letters, read by VoiceOver as one element ("Afzender. Brief 1: … Brief 2: … Verschilt").
private struct CompareRowView: View {
    let row: DuplicateModel.CompareRow
    let letterTitles: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(row.title)
                .font(.subheadline.weight(.semibold))
            AdaptiveStack(spacing: 16) {
                value(title: letterTitles.first, row.first)
                value(title: letterTitles.last, row.second)
            }
            if let markText = row.markText {
                Label(markText, systemImage: markSymbol)
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.accessibilityLabel)
    }

    /// A symbol beside the words, so the mark never rests on colour alone.
    private var markSymbol: String {
        switch row.mark {
        case .mayDiffer: "questionmark.circle"
        case .differs, nil: "exclamationmark.triangle.fill"
        }
    }

    private func value(title: String?, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if let title {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// "Samenvoegen?": what a merge does, "Taak ook afronden" when a task is done on the other scan, and the answer.
private struct MergeQuestion: View {
    @Bindable var model: DuplicateModel

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(DocumentStrings.duplicateMergeMessage)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !model.twinNotes.isEmpty {
                    Section {
                        Toggle(DocumentStrings.duplicateCompleteTask, isOn: $model.completeTwinTasks)
                        ForEach(model.twinNotes, id: \.self) { note in
                            Text(note)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                Section {
                    PrimaryButton(DocumentStrings.duplicateMergeConfirm) { Task { await model.merge() } }
                        .disabled(model.isSaving)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(DocumentStrings.duplicateMergeTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(DocumentStrings.duplicateMergeCancel) { model.asksToMerge = false }
                }
            }
        }
    }
}
#endif
