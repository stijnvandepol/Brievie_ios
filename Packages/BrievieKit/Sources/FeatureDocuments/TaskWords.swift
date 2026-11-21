import BrievieCore
import Foundation

/// The words of a task row in "Mijn taken" (spec S 6). The server counts the days and decides the group and the
/// reason (Europe/Amsterdam); these only put them into words, in the user's language and region.
enum TaskWords {
    /// "Vandaag", "Morgen", "Nog 5 dagen (1 dec)", "3 dagen te laat (18 nov)"; `nil` without a date.
    static func when(_ task: WorkspaceTask, locale: Locale = .autoupdatingCurrent) -> String? {
        guard let deadline = task.deadline, let daysLeft = task.daysLeft else { return nil }
        let date = day(deadline, locale: locale)
        switch daysLeft {
        case 0: return DocumentStrings.taskToday
        case 1: return DocumentStrings.taskTomorrow
        case 2...: return DocumentStrings.taskDaysLeft(daysLeft, date: date)
        default: return DocumentStrings.taskLate(-daysLeft, date: date)
        }
    }

    /// Past the deadline by the server's today.
    static func isLate(_ task: WorkspaceTask) -> Bool {
        (task.daysLeft ?? 0) < 0
    }

    static func groupTitle(_ group: TaskGroup) -> String? {
        switch group {
        case .overdue: DocumentStrings.taskGroupOverdue
        case .withinWeek: DocumentStrings.taskGroupWithinWeek
        case .later: DocumentStrings.taskGroupLater
        case .noDate: DocumentStrings.taskGroupNoDate
        case .none, .unknown: nil
        }
    }

    /// "€ 1.234,56" in the user's notation; `nil` when unknown.
    static func amount(_ task: WorkspaceTask, locale: Locale = .autoupdatingCurrent) -> String? {
        task.amount.map { $0.formatted(.currency(code: "EUR").locale(locale)) }
    }

    /// Whose task it is (the web's `forText`): "Voor jou en Piet", "Voor Finance", "Zonder naam",
    /// "Aan jou gegeven door Anne", "Jij doet dit", "Bij Piet". `me` is the reader's own name.
    static func whose(_ task: WorkspaceTask, me myName: String, locale: Locale = .autoupdatingCurrent) -> String? {
        let others = task.forNames.isEmpty ? nil : task.forNames.formatted(.list(type: .and).locale(locale))
        switch task.reason {
        case .assigned:
            if task.assignedByName.isEmpty || task.assignedByName == myName { return DocumentStrings.taskYouDoThis }
            return String(format: DocumentStrings.taskHandedByFormat, task.assignedByName)
        case .addressee:
            return others.map { String(format: DocumentStrings.taskForYouAndFormat, $0) } ?? DocumentStrings.taskForYou
        case .unassigned:
            return others.map { String(format: DocumentStrings.taskForFormat, $0) } ?? DocumentStrings.taskNoName
        default:
            if !task.assignedToName.isEmpty {
                return String(format: DocumentStrings.taskWithFormat, task.assignedToName)
            }
            return others.map { String(format: DocumentStrings.taskForFormat, $0) }
        }
    }

    /// "Van Belastingdienst · Voor jou"; either part may be absent.
    static func fromFor(_ task: WorkspaceTask, me myName: String, locale: Locale = .autoupdatingCurrent) -> String? {
        let parts = [
            task.sender.isEmpty ? nil : String(format: DocumentStrings.taskFromFormat, task.sender),
            whose(task, me: myName, locale: locale)
        ].compactMap(\.self)
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// Where the date came from: the letter's words, or typed in by a person.
    static func why(_ task: WorkspaceTask) -> String? {
        guard task.deadline != nil else { return nil }
        switch task.deadlineSource {
        case "in_document" where !task.deadlineQuote.isEmpty:
            return String(format: DocumentStrings.taskFromLetterFormat, task.deadlineQuote)
        case "manual":
            return DocumentStrings.taskDateByHand
        default:
            return nil
        }
    }

    /// The letter names a term but no date: the term, and what to do.
    static func needsDate(_ task: WorkspaceTask) -> String? {
        guard task.needsDeadline else { return nil }
        if task.termQuote.isEmpty { return DocumentStrings.taskNeedsDateNoTerm }
        return String(format: DocumentStrings.taskNeedsDateTermFormat, task.termQuote)
    }

    /// The kind of task ("Betalen") when the description does not already start with it.
    static func typeWord(_ task: WorkspaceTask) -> String? {
        guard !task.type.isEmpty else { return nil }
        let label = DocumentTypes.taskTypeLabel(task.type)
        let starts = task.description.range(of: label, options: [.caseInsensitive, .anchored]) != nil
        return starts ? nil : label
    }

    /// "Afgevinkt door Anne op 20 nov" / "Afgevinkt op 20 nov", the day in the phone's time zone.
    static func doneLine(_ task: WorkspaceTask, locale: Locale = .autoupdatingCurrent) -> String? {
        guard let completedAt = task.completedAt else { return nil }
        let date = completedAt.formatted(Date.FormatStyle(locale: locale).day().month(.abbreviated))
        if task.completedByName.isEmpty { return String(format: DocumentStrings.taskDoneOnFormat, date) }
        return String(format: DocumentStrings.taskDoneByFormat, task.completedByName, date)
    }

    /// The VoiceOver name of the tick box: "Klaar: Betaal de aanslag".
    static func tickLabel(_ task: WorkspaceTask) -> String {
        String(format: DocumentStrings.taskTickFormat, task.description)
    }

    /// What VoiceOver reads for the row: the action, when, the amount, from and for whom, why, and a missing date.
    static func accessibilityLabel(
        _ task: WorkspaceTask, me myName: String, locale: Locale = .autoupdatingCurrent
    ) -> String {
        [
            task.description, when(task, locale: locale), amount(task, locale: locale),
            fromFor(task, me: myName, locale: locale), why(task), needsDate(task)
        ].compactMap(\.self).joined(separator: ", ")
    }

    /// A day as "1 dec" / "1 Dec" / "Dec 1": noon of the day in the phone's zone, so no zone moves it.
    static func day(_ date: CalendarDate, locale: Locale) -> String {
        date.date(in: .current).formatted(Date.FormatStyle(locale: locale).day().month(.abbreviated))
    }
}
