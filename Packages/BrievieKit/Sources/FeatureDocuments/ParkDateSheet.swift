#if os(iOS)
import BrievieCore
import BrievieUI
import SwiftUI

/// "Wacht op reactie…" and "Uitstellen…": a day within `range` (after today, at most a year; a snooze not past the
/// task's date), and the way back when the task has one already.
struct ParkDateSheet: View {
    enum Kind {
        case waiting
        case snooze
    }

    let kind: Kind
    let title: String
    let current: CalendarDate?
    let range: ClosedRange<CalendarDate>
    let error: String?
    let save: (CalendarDate?) -> Void
    let cancel: () -> Void
    @State private var day: Date

    init(
        kind: Kind, title: String, current: CalendarDate?, range: ClosedRange<CalendarDate>, error: String?,
        save: @escaping (CalendarDate?) -> Void, cancel: @escaping () -> Void
    ) {
        self.kind = kind
        self.title = title
        self.current = current
        self.range = range
        self.error = error
        self.save = save
        self.cancel = cancel
        let start = current.map { min(max($0, range.lowerBound), range.upperBound) } ?? range.lowerBound
        _day = State(initialValue: start.date(in: .current))
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(title).font(.headline)
                    Text(question).fixedSize(horizontal: false, vertical: true)
                    Text(hint).font(.subheadline).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let error { ErrorBanner(error) }
                }
                Section {
                    DatePicker(
                        question, selection: $day,
                        in: range.lowerBound.date(in: .current)...range.upperBound.date(in: .current),
                        displayedComponents: .date
                    )
                    .datePickerStyle(.graphical)
                    .tint(BrievieColor.brand)
                }
                if current != nil {
                    Section {
                        Button(stopLabel, role: .destructive) { save(nil) }
                    }
                }
            }
            .navigationTitle(kind == .waiting ? DocumentStrings.letterStatusWaiting : DocumentStrings.groupSnoozed)
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

    private var question: String {
        kind == .waiting ? DocumentStrings.waitQuestion : DocumentStrings.snoozeQuestion
    }

    private var hint: String {
        kind == .waiting ? DocumentStrings.waitHint : DocumentStrings.snoozeHint
    }

    private var stopLabel: String {
        kind == .waiting ? DocumentStrings.waitStop : DocumentStrings.snoozeStop
    }
}
#endif
