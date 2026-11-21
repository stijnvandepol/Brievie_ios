#if os(iOS)
import BrievieCore
import BrievieUI
import SwiftUI

/// "Geef aan…": the people who may read the letter, names only, as the server lists them.
struct HandOverSheet: View {
    let title: String
    let people: [TaskAssignee]
    let emptyText: String?
    let error: String?
    let choose: (UUID) -> Void
    let cancel: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(title).font(.headline)
                    Text(DocumentStrings.myTasksHandOverIntro)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if let error { ErrorBanner(error) }
                }
                Section {
                    if let emptyText {
                        Text(emptyText).foregroundStyle(.secondary)
                    }
                    ForEach(people) { person in
                        Button {
                            choose(person.id)
                        } label: {
                            Label {
                                Text(person.name).foregroundStyle(.primary)
                            } icon: {
                                Image(systemName: "person.crop.circle").foregroundStyle(BrievieColor.brand)
                            }
                        }
                        .frame(minHeight: 44)
                    }
                }
            }
            .navigationTitle(DocumentStrings.myTasksHandOverTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(DocumentStrings.myTasksSetDateCancel, action: cancel)
                }
            }
        }
    }
}

/// "Datum invullen": the day the letter names, with its term above the calendar.
struct SetDateSheet: View {
    let title: String
    let term: String?
    let current: CalendarDate?
    let error: String?
    let save: (CalendarDate?) -> Void
    let cancel: () -> Void
    @State private var day: Date

    init(
        title: String, term: String?, current: CalendarDate?, error: String?,
        save: @escaping (CalendarDate?) -> Void, cancel: @escaping () -> Void
    ) {
        self.title = title
        self.term = term
        self.current = current
        self.error = error
        self.save = save
        self.cancel = cancel
        _day = State(initialValue: (current ?? CalendarDate(Date(), in: .current)).date(in: .current))
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(title).font(.headline)
                    // The question is too long for the bar ("Which date does the l..."): it stands here in full.
                    Text(DocumentStrings.myTasksSetDateTitle)
                        .fixedSize(horizontal: false, vertical: true)
                    if let term {
                        Text(String(format: DocumentStrings.taskNeedsDateTermFormat, term))
                            .font(.subheadline)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let error { ErrorBanner(error) }
                }
                Section {
                    DatePicker(
                        DocumentStrings.myTasksSetDateTitle, selection: $day, displayedComponents: .date
                    )
                    .datePickerStyle(.graphical)
                    .tint(BrievieColor.brand)
                }
                if current != nil {
                    Section {
                        Button(DocumentStrings.myTasksSetDateRemove, role: .destructive) { save(nil) }
                    }
                }
            }
            .navigationTitle(DocumentStrings.myTasksSetDate)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(DocumentStrings.myTasksSetDateCancel, action: cancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(DocumentStrings.myTasksSetDateSave) { save(CalendarDate(day, in: .current)) }
                }
            }
        }
    }
}
#endif
