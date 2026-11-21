import Foundation

extension DocumentStrings {
    // "Mijn taken": the words of a task row
    static let taskToday = String(localized: "tasks.when.today", defaultValue: "Vandaag", bundle: .module)
    static let taskTomorrow = String(localized: "tasks.when.tomorrow", defaultValue: "Morgen", bundle: .module)

    /// More than one day left. The catalog has the singular and plural; the default carries the right Dutch form
    /// (`swift test` reads no catalogs).
    static func taskDaysLeft(_ days: Int, date: String) -> String {
        days == 1
            ? String(localized: "tasks.when.daysLeft", defaultValue: "Nog \(days) dag (\(date))", bundle: .module)
            : String(localized: "tasks.when.daysLeft", defaultValue: "Nog \(days) dagen (\(date))", bundle: .module)
    }

    /// `days` (at least 1) days past the deadline.
    static func taskLate(_ days: Int, date: String) -> String {
        days == 1
            ? String(localized: "tasks.when.late", defaultValue: "\(days) dag te laat (\(date))", bundle: .module)
            : String(localized: "tasks.when.late", defaultValue: "\(days) dagen te laat (\(date))", bundle: .module)
    }

    static let taskGroupOverdue = String(localized: "tasks.group.overdue", defaultValue: "Te laat", bundle: .module)
    static let taskGroupWithinWeek = String(
        localized: "tasks.group.withinWeek", defaultValue: "Binnen 7 dagen", bundle: .module
    )
    static let taskGroupLater = String(localized: "tasks.group.later", defaultValue: "Later", bundle: .module)
    static let taskGroupNoDate = String(localized: "tasks.group.noDate", defaultValue: "Zonder datum", bundle: .module)
    static let taskFromFormat = String(localized: "tasks.from", defaultValue: "Van %@", bundle: .module)
    static let taskForYou = String(localized: "tasks.for.you", defaultValue: "Voor jou", bundle: .module)
    static let taskForYouAndFormat = String(
        localized: "tasks.for.youAnd", defaultValue: "Voor jou en %@", bundle: .module
    )
    static let taskForFormat = String(localized: "tasks.for.others", defaultValue: "Voor %@", bundle: .module)
    static let taskNoName = String(localized: "tasks.for.noName", defaultValue: "Zonder naam", bundle: .module)
    static let taskWithFormat = String(localized: "tasks.for.with", defaultValue: "Bij %@", bundle: .module)
    static let taskYouDoThis = String(localized: "tasks.for.mine", defaultValue: "Jij doet dit", bundle: .module)
    static let taskHandedByFormat = String(
        localized: "tasks.for.handedBy", defaultValue: "Aan jou gegeven door %@", bundle: .module
    )
    static let taskFromLetterFormat = String(
        localized: "tasks.why.letter", defaultValue: "Uit de brief: ‘%@’", bundle: .module
    )
    static let taskDateByHand = String(
        localized: "tasks.why.manual", defaultValue: "Datum zelf ingevuld", bundle: .module
    )
    static let taskNeedsDate = String(localized: "tasks.needsDate", defaultValue: "Datum nodig", bundle: .module)
    static let taskNeedsDateTermFormat = String(
        localized: "tasks.needsDate.term",
        defaultValue: "De brief noemt een termijn: ‘%@’. Vul de datum in.",
        bundle: .module
    )
    static let taskNeedsDateNoTerm = String(
        localized: "tasks.needsDate.noTerm", defaultValue: "Vul de datum in.", bundle: .module
    )
    static let taskTickFormat = String(localized: "tasks.tick", defaultValue: "Klaar: %@", bundle: .module)
    static let taskDoneByFormat = String(
        localized: "tasks.done.by", defaultValue: "Afgevinkt door %1$@ op %2$@", bundle: .module
    )
    static let taskDoneOnFormat = String(localized: "tasks.done.on", defaultValue: "Afgevinkt op %@", bundle: .module)

    /// The plain keys of "Mijn taken" with the text the code resolves, for the catalog parity test.
    static var myTasksAll: [String: String] {
        [
            "tasks.when.today": taskToday, "tasks.when.tomorrow": taskTomorrow,
            "tasks.group.overdue": taskGroupOverdue, "tasks.group.withinWeek": taskGroupWithinWeek,
            "tasks.group.later": taskGroupLater, "tasks.group.noDate": taskGroupNoDate,
            "tasks.from": taskFromFormat, "tasks.for.you": taskForYou, "tasks.for.youAnd": taskForYouAndFormat,
            "tasks.for.others": taskForFormat, "tasks.for.noName": taskNoName, "tasks.for.with": taskWithFormat,
            "tasks.for.mine": taskYouDoThis, "tasks.for.handedBy": taskHandedByFormat,
            "tasks.why.letter": taskFromLetterFormat, "tasks.why.manual": taskDateByHand,
            "tasks.needsDate": taskNeedsDate, "tasks.needsDate.term": taskNeedsDateTermFormat,
            "tasks.needsDate.noTerm": taskNeedsDateNoTerm, "tasks.tick": taskTickFormat,
            "tasks.done.by": taskDoneByFormat, "tasks.done.on": taskDoneOnFormat
        ]
    }
}
