import Foundation

// Letter status, waiting and snoozing (host PR #50), and the account messages that come with the server's
// security rules. Texts from the briefstatus spec, section 12.
extension DocumentStrings {
    static let secondFactorRequired = String(
        localized: "error.secondFactorRequired",
        defaultValue: "Stel eerst tweestapsverificatie in op de webinterface.",
        bundle: .module
    )
    static let letterStatusNew = String(
        localized: "status.new",
        defaultValue: "Nieuw",
        bundle: .module
    )
    static let letterStatusOpen = String(
        localized: "status.open",
        defaultValue: "Openstaand",
        bundle: .module
    )
    static let letterStatusWaiting = String(
        localized: "status.waiting",
        defaultValue: "Wacht op reactie",
        bundle: .module
    )
    static let letterStatusWaitingUntilFormat = String(
        localized: "status.waitingUntil",
        defaultValue: "Wacht op reactie tot %@",
        bundle: .module
    )
    static let letterStatusHandled = String(
        localized: "status.handled",
        defaultValue: "Afgehandeld",
        bundle: .module
    )
    static let letterStatusOverdue = String(
        localized: "status.overdue",
        defaultValue: "Te laat",
        bundle: .module
    )
    static let handleButton = String(
        localized: "handle.button",
        defaultValue: "Brief afhandelen",
        bundle: .module
    )
    static let handleTitle = String(
        localized: "handle.title",
        defaultValue: "Brief afhandelen?",
        bundle: .module
    )
    static let handleTasks = String(
        localized: "handle.tasks",
        defaultValue: "Deze taken worden afgevinkt:",
        bundle: .module
    )
    static let handleNoTasks = String(
        localized: "handle.noTasks",
        defaultValue: "Er staat geen taak meer open.",
        bundle: .module
    )
    static let handlePayment = String(
        localized: "handle.payment",
        defaultValue: "De betaling is gedaan of geregeld",
        bundle: .module
    )
    static let handleConfirm = String(
        localized: "handle.confirm",
        defaultValue: "Afhandelen",
        bundle: .module
    )
    static let errorTasksChanged = String(
        localized: "error.tasksChanged",
        defaultValue: "De taken van deze brief zijn net veranderd. Bekijk ze opnieuw.",
        bundle: .module
    )
    static let errorPaymentNotConfirmed = String(
        localized: "error.paymentNotConfirmed",
        defaultValue: "Vink aan dat de betaling is gedaan of geregeld.",
        bundle: .module
    )
    static let errorNotReviewed = String(
        localized: "error.notReviewed",
        defaultValue: "Deze brief is nog niet nagekeken.",
        bundle: .module
    )
    static let errorTaskDone = String(
        localized: "error.taskDone",
        defaultValue: "Deze taak is al afgerond.",
        bundle: .module
    )
    static let errorSnoozeAfterDeadline = String(
        localized: "error.snoozeAfterDeadline",
        defaultValue: "Je kunt niet uitstellen tot na de datum van de taak.",
        bundle: .module
    )
    static let errorDateRange = String(
        localized: "error.dateRange",
        defaultValue: "Kies een datum na vandaag, binnen een jaar.",
        bundle: .module
    )
    static let waitAction = String(
        localized: "wait.action",
        defaultValue: "Wacht op reactie…",
        bundle: .module
    )
    static let waitQuestion = String(
        localized: "wait.question",
        defaultValue: "Tot wanneer wacht je op een reactie?",
        bundle: .module
    )
    static let waitHint = String(
        localized: "wait.hint",
        defaultValue: "Op die dag komt de taak terug in Mijn taken. Iedereen die deze brief ziet, ziet dat je wacht.",
        bundle: .module
    )
    static let waitStop = String(
        localized: "wait.stop",
        defaultValue: "Niet meer wachten",
        bundle: .module
    )
    static let waitOverFormat = String(
        localized: "wait.over",
        defaultValue: "Wachten voorbij sinds %@",
        bundle: .module
    )
    static let snoozeAction = String(
        localized: "snooze.action",
        defaultValue: "Uitstellen…",
        bundle: .module
    )
    static let snoozeQuestion = String(
        localized: "snooze.question",
        defaultValue: "Tot wanneer stel je dit uit?",
        bundle: .module
    )
    static let snoozeHint = String(
        localized: "snooze.hint",
        defaultValue: """
            Alleen jij ziet dat je dit uitstelt. Op die dag staat de taak weer in je lijst. \
            Uitstellen kan tot de datum van de taak.
            """,
        bundle: .module
    )
    static let snoozeUntilFormat = String(
        localized: "snooze.until",
        defaultValue: "Uitgesteld tot %@",
        bundle: .module
    )
    static let snoozeStop = String(
        localized: "snooze.stop",
        defaultValue: "Niet meer uitstellen",
        bundle: .module
    )
    static let groupWaiting = String(
        localized: "tasks.group.waiting",
        defaultValue: "Wacht op reactie",
        bundle: .module
    )
    static let groupSnoozed = String(
        localized: "tasks.group.snoozed",
        defaultValue: "Uitgesteld",
        bundle: .module
    )

    static let status: [String: String] = [
        "error.secondFactorRequired": secondFactorRequired,
        "status.new": letterStatusNew,
        "status.open": letterStatusOpen,
        "status.waiting": letterStatusWaiting,
        "status.waitingUntil": letterStatusWaitingUntilFormat,
        "status.handled": letterStatusHandled,
        "status.overdue": letterStatusOverdue,
        "handle.button": handleButton,
        "handle.title": handleTitle,
        "handle.tasks": handleTasks,
        "handle.noTasks": handleNoTasks,
        "handle.payment": handlePayment,
        "handle.confirm": handleConfirm,
        "error.tasksChanged": errorTasksChanged,
        "error.paymentNotConfirmed": errorPaymentNotConfirmed,
        "error.notReviewed": errorNotReviewed,
        "error.taskDone": errorTaskDone,
        "error.snoozeAfterDeadline": errorSnoozeAfterDeadline,
        "error.dateRange": errorDateRange,
        "wait.action": waitAction,
        "wait.question": waitQuestion,
        "wait.hint": waitHint,
        "wait.stop": waitStop,
        "wait.over": waitOverFormat,
        "snooze.action": snoozeAction,
        "snooze.question": snoozeQuestion,
        "snooze.hint": snoozeHint,
        "snooze.until": snoozeUntilFormat,
        "snooze.stop": snoozeStop,
        "tasks.group.waiting": groupWaiting,
        "tasks.group.snoozed": groupSnoozed
    ]
}
