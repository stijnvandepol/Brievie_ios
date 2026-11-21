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

    // "Mijn taken": the screen
    static let myTasksTitle = String(localized: "tasks.title", defaultValue: "Mijn taken", bundle: .module)
    static let myTasksFilterLabel = String(
        localized: "tasks.filter.label", defaultValue: "Welke taken", bundle: .module
    )
    static let myTasksFilterMine = String(localized: "tasks.filter.mine", defaultValue: "Mijn taken", bundle: .module)
    static let myTasksFilterAll = String(localized: "tasks.filter.all", defaultValue: "Alle taken", bundle: .module)
    static let myTasksTabLabel = String(localized: "tasks.tab.label", defaultValue: "Taken", bundle: .module)
    static let myTasksTabOpen = String(localized: "tasks.tab.open", defaultValue: "Open", bundle: .module)
    static let myTasksTabDone = String(localized: "tasks.tab.done", defaultValue: "Afgerond", bundle: .module)
    static let myTasksDescriptionHome = String(
        localized: "tasks.description.home",
        defaultValue: "Wat je met je post moet doen, op datum. Je hoeft de brief er niet voor te openen.",
        bundle: .module
    )
    static let myTasksDescriptionBusiness = String(
        localized: "tasks.description.business",
        defaultValue: "Taken die bij jou horen. Taken van je afdeling en post zonder naam staan bij Op te pakken.",
        bundle: .module
    )
    static let myTasksToPickUp = String(localized: "tasks.toPickUp", defaultValue: "Op te pakken", bundle: .module)
    static let myTasksToPickUpEmpty = String(
        localized: "tasks.toPickUp.empty", defaultValue: "Er ligt niets op te pakken.", bundle: .module
    )
    static let myTasksEmptyOpen = String(
        localized: "tasks.empty.open",
        defaultValue: "Je hebt geen open taken. Nieuwe taken komen hier vanzelf zodra je post is nagekeken.",
        bundle: .module
    )
    static let myTasksEmptyDone = String(
        localized: "tasks.empty.done", defaultValue: "Je hebt de laatste 30 dagen niets afgevinkt.", bundle: .module
    )
    static let myTasksNoPerson = String(
        localized: "tasks.notice.noPerson",
        defaultValue: """
        Je account hangt nog niet aan een naam. Daarom zie je hier alleen taken die iemand aan je geeft. \
        Vraag een beheerder om je te koppelen bij Personen.
        """,
        bundle: .module
    )
    static let myTasksViewer = String(
        localized: "tasks.notice.viewer", defaultValue: "Je kunt taken bekijken, maar niet afvinken.", bundle: .module
    )
    static let myTasksTruncated = String(
        localized: "tasks.notice.truncated", defaultValue: "Alleen de eerste 500 taken worden getoond.", bundle: .module
    )

    /// `count` (at least 1) letters still wait for a review.
    static func myTasksWaiting(_ count: Int) -> String {
        count == 1
            ? String(
                localized: "tasks.waiting",
                defaultValue: "Er wacht nog \(count) brief op nakijken. Daar kunnen nieuwe taken uit komen.",
                bundle: .module
            )
            : String(
                localized: "tasks.waiting",
                defaultValue: "Er wachten nog \(count) brieven op nakijken. Daar kunnen nieuwe taken uit komen.",
                bundle: .module
            )
    }

    static let myTasksShowInbox = String(localized: "tasks.showInbox", defaultValue: "Naar Inbox", bundle: .module)
    static let myTasksUndo = String(localized: "tasks.undo", defaultValue: "Ongedaan maken", bundle: .module)
    static let myTasksNotDone = String(localized: "tasks.notDone", defaultValue: "Toch niet klaar", bundle: .module)
    static let myTasksAnnounceDoneFormat = String(
        localized: "tasks.announce.done", defaultValue: "Afgevinkt: %@", bundle: .module
    )
    static let myTasksAnnounceOpenFormat = String(
        localized: "tasks.announce.open", defaultValue: "Weer open: %@", bundle: .module
    )
    static let myTasksNotSupported = String(
        localized: "tasks.notSupported",
        defaultValue: "Je server kent Mijn taken nog niet. Werk Brievie op de server bij.",
        bundle: .module
    )
    static let myTasksStateDone = String(localized: "tasks.done.state", defaultValue: "Klaar", bundle: .module)
    static let myTasksStateOpen = String(localized: "tasks.open.state", defaultValue: "Open", bundle: .module)

    // "Mijn taken": picking up, handing over and dating a task
    static let myTasksTakeOn = String(localized: "tasks.takeOn", defaultValue: "Ik doe dit", bundle: .module)
    static let myTasksRelease = String(localized: "tasks.release", defaultValue: "Niet meer aan mij", bundle: .module)
    static let myTasksHandOver = String(localized: "tasks.handOver", defaultValue: "Geef aan…", bundle: .module)
    static let myTasksHandOverTitle = String(
        localized: "tasks.handOver.title", defaultValue: "Aan wie geef je deze taak?", bundle: .module
    )
    static let myTasksHandOverIntro = String(
        localized: "tasks.handOver.intro", defaultValue: "Alleen wie deze brief mag lezen, staat in de lijst.",
        bundle: .module
    )
    static let myTasksHandOverNobody = String(
        localized: "tasks.handOver.nobody", defaultValue: "Er is niemand anders die deze brief mag lezen.",
        bundle: .module
    )
    static let myTasksSetDate = String(localized: "tasks.setDate", defaultValue: "Datum invullen", bundle: .module)
    static let myTasksSetDateTitle = String(
        localized: "tasks.setDate.title", defaultValue: "Welke datum noemt de brief?", bundle: .module
    )
    static let myTasksSetDateSave = String(localized: "tasks.setDate.save", defaultValue: "Opslaan", bundle: .module)
    static let myTasksSetDateCancel = String(
        localized: "tasks.setDate.cancel", defaultValue: "Annuleren", bundle: .module
    )
    static let myTasksSetDateRemove = String(
        localized: "tasks.setDate.remove", defaultValue: "Datum weghalen", bundle: .module
    )
    static let myTasksCannotRead = String(
        localized: "tasks.error.cannotRead", defaultValue: "Deze persoon mag de brief niet lezen. Kies iemand anders.",
        bundle: .module
    )
    static let myTasksWithoutLetter = String(
        localized: "tasks.error.withoutLetter",
        defaultValue: "Deze taak hoort niet bij een brief en kan niet worden gegeven.",
        bundle: .module
    )
    static let myTasksDateBeforeLetter = String(
        localized: "tasks.error.dateBeforeLetter", defaultValue: "Die datum ligt voor de datum van de brief.",
        bundle: .module
    )
    static let myTasksTaken = String(
        localized: "tasks.error.taken",
        defaultValue: "Iemand anders doet deze taak al. Vraag die persoon of een beheerder om hem door te geven.",
        bundle: .module
    )

    static let myTasksOpenLetter = String(
        localized: "tasks.openLetter", defaultValue: "Brief bekijken", bundle: .module
    )
    static let myTasksTickAction = String(localized: "tasks.tickAction", defaultValue: "Afvinken", bundle: .module)

    // "Mijn taken" next to the Inbox
    static let myTasksMenuCountFormat = String(
        localized: "tasks.menu.count", defaultValue: "Mijn taken · %lld open", bundle: .module
    )
    static let myTasksMenuCountLateFormat = String(
        localized: "tasks.menu.countLate", defaultValue: "Mijn taken · %1$lld open, %2$lld te laat", bundle: .module
    )
    static let myTasksLinkCountFormat = String(
        localized: "tasks.link.count", defaultValue: "Mijn taken: %lld open", bundle: .module
    )
    static let myTasksLinkCountLateFormat = String(
        localized: "tasks.link.countLate", defaultValue: "Mijn taken: %1$lld open, waarvan %2$lld te laat",
        bundle: .module
    )

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
            "tasks.done.by": taskDoneByFormat, "tasks.done.on": taskDoneOnFormat,
            "tasks.title": myTasksTitle, "tasks.filter.label": myTasksFilterLabel,
            "tasks.filter.mine": myTasksFilterMine, "tasks.filter.all": myTasksFilterAll,
            "tasks.tab.label": myTasksTabLabel, "tasks.tab.open": myTasksTabOpen, "tasks.tab.done": myTasksTabDone,
            "tasks.description.home": myTasksDescriptionHome, "tasks.description.business": myTasksDescriptionBusiness,
            "tasks.toPickUp": myTasksToPickUp, "tasks.toPickUp.empty": myTasksToPickUpEmpty,
            "tasks.empty.open": myTasksEmptyOpen, "tasks.empty.done": myTasksEmptyDone,
            "tasks.notice.noPerson": myTasksNoPerson, "tasks.notice.viewer": myTasksViewer,
            "tasks.notice.truncated": myTasksTruncated, "tasks.showInbox": myTasksShowInbox,
            "tasks.undo": myTasksUndo, "tasks.notDone": myTasksNotDone,
            "tasks.announce.done": myTasksAnnounceDoneFormat, "tasks.announce.open": myTasksAnnounceOpenFormat,
            "tasks.notSupported": myTasksNotSupported, "tasks.done.state": myTasksStateDone,
            "tasks.open.state": myTasksStateOpen, "tasks.takeOn": myTasksTakeOn, "tasks.release": myTasksRelease,
            "tasks.handOver": myTasksHandOver, "tasks.handOver.title": myTasksHandOverTitle,
            "tasks.handOver.intro": myTasksHandOverIntro, "tasks.handOver.nobody": myTasksHandOverNobody,
            "tasks.setDate": myTasksSetDate, "tasks.setDate.title": myTasksSetDateTitle,
            "tasks.setDate.save": myTasksSetDateSave, "tasks.setDate.cancel": myTasksSetDateCancel,
            "tasks.setDate.remove": myTasksSetDateRemove, "tasks.error.cannotRead": myTasksCannotRead,
            "tasks.error.withoutLetter": myTasksWithoutLetter, "tasks.error.dateBeforeLetter": myTasksDateBeforeLetter,
            "tasks.error.taken": myTasksTaken, "tasks.openLetter": myTasksOpenLetter,
            "tasks.tickAction": myTasksTickAction, "tasks.menu.count": myTasksMenuCountFormat,
            "tasks.menu.countLate": myTasksMenuCountLateFormat, "tasks.link.count": myTasksLinkCountFormat,
            "tasks.link.countLate": myTasksLinkCountLateFormat
        ]
    }
}
