#if os(iOS)
import BrievieUI
import SwiftUI

/// What a task row can do besides ticking; `nil` hides the action.
struct MyTaskRowActions {
    var takeOn: (() -> Void)?
    var release: (() -> Void)?
    var handOver: (() -> Void)?
    var setDate: (() -> Void)?
    var openLetter: (() -> Void)?
    /// "Wacht op reactie…" / "Niet meer wachten", "Uitstellen…" / "Niet meer uitstellen" (host PR #50).
    var wait: (() -> Void)?
    var stopWaiting: (() -> Void)?
    var snooze: (() -> Void)?
    var unsnooze: (() -> Void)?
}

/// One task: the tick box, what to do, when (late in the warning colour and in words), the amount, from and for
/// whom, why, a missing date, and the letter. VoiceOver reads it as one element whose actions are the buttons.
/// `badge` is the slot a later letter-status design fills; nothing fills it now.
struct MyTaskRowView<Badge: View>: View {
    let row: MyTasksModel.Row
    let tick: (Bool) -> Void
    let actions: MyTaskRowActions
    /// "Ongedaan maken" on the open list, "Toch niet klaar" on the done list.
    let undoLabel: String
    private let badge: Badge

    init(
        row: MyTasksModel.Row, tick: @escaping (Bool) -> Void, actions: MyTaskRowActions, undoLabel: String,
        @ViewBuilder badge: () -> Badge = { EmptyView() }
    ) {
        self.row = row
        self.tick = tick
        self.actions = actions
        self.undoLabel = undoLabel
        self.badge = badge()
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            tickBox
            details
            badge
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.accessibilityLabel)
        .accessibilityValue(row.isTicked ? DocumentStrings.myTasksStateDone : DocumentStrings.myTasksStateOpen)
        .accessibilityAddTraits(row.canTick ? .isButton : [])
        .accessibilityAction(.default) { if row.canTick { tick(!row.isTicked) } }
        .accessibilityActions { actionButtons(includingTick: true) }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            if row.canTick {
                Button(row.isTicked ? undoLabel : DocumentStrings.myTasksTickAction) { tick(!row.isTicked) }
                    .tint(BrievieColor.brand)
            }
        }
        .swipeActions(edge: .trailing) {
            if let takeOn = actions.takeOn { Button(DocumentStrings.myTasksTakeOn, action: takeOn) }
            if let handOver = actions.handOver { Button(DocumentStrings.myTasksHandOver, action: handOver) }
        }
        .contextMenu { actionButtons(includingTick: false) }
    }

    @ViewBuilder private var tickBox: some View {
        let mark = Image(systemName: tickSymbol)
            .font(.title2)
            .foregroundStyle(row.isTicked ? BrievieColor.brand : Color.secondary)
            .frame(minWidth: 44, minHeight: 44)
        if row.canTick {
            Button { tick(!row.isTicked) } label: { mark }
                .buttonStyle(.borderless)
                .accessibilityLabel(row.tickLabel)
        } else {
            mark
        }
    }

    private var tickSymbol: String {
        if row.isTicked { return "checkmark.circle.fill" }
        return "circle"
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(row.title)
                .font(.headline)
                .strikethrough(row.isTicked)
                .foregroundStyle(row.isTicked ? .secondary : .primary)
            if let typeWord = row.typeWord {
                Text(typeWord).font(.subheadline).foregroundStyle(.secondary)
            }
            if let parked = row.parkedLine {
                Label(parked, systemImage: "hourglass").font(.subheadline).foregroundStyle(.secondary)
            }
            if row.when != nil || row.amount != nil {
                AdaptiveStack(spacing: 12) {
                    if let when = row.when { whenLabel(when) }
                    if let amount = row.amount {
                        Text(amount).brievieNumber(.title3)
                    }
                }
            }
            if let fromFor = row.fromFor {
                Text(fromFor).font(.subheadline).foregroundStyle(.secondary)
            }
            if let why = row.why {
                Text(why).font(.footnote).foregroundStyle(.secondary)
            }
            if let needsDate = row.needsDate { needsDateBlock(needsDate) }
            if let doneLine = row.doneLine {
                Text(doneLine).font(.footnote).foregroundStyle(.secondary)
            }
            visibleButtons
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Late: the warning colour and a symbol, and always the words ("3 dagen te laat").
    @ViewBuilder private func whenLabel(_ when: String) -> some View {
        if row.isLate {
            Label(when, systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(BrievieColor.warning)
        } else {
            Label(when, systemImage: "calendar")
                .font(.subheadline.weight(.semibold))
        }
    }

    private func needsDateBlock(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(DocumentStrings.taskNeedsDate)
                .font(.caption.weight(.semibold))
                .foregroundStyle(BrievieColor.warning)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .overlay(Capsule().stroke(BrievieColor.warning))
            Text(text).font(.subheadline)
        }
    }

    /// The buttons a row shows: undo on a struck row, the date for "Datum nodig", "Ik doe dit", and the letter.
    private var visibleButtons: some View {
        AdaptiveStack(spacing: 16) {
            if row.isTicked, row.canTick {
                Button(undoLabel) { tick(false) }
            }
            if row.needsDate != nil, let setDate = actions.setDate {
                Button(DocumentStrings.myTasksSetDate, action: setDate)
            }
            if let takeOn = actions.takeOn {
                Button(DocumentStrings.myTasksTakeOn, action: takeOn).fontWeight(.semibold)
            }
            if let openLetter = actions.openLetter {
                Button(DocumentStrings.myTasksOpenLetter, action: openLetter).foregroundStyle(.secondary)
            }
        }
        .font(.subheadline)
        .buttonStyle(.borderless)
        .frame(minHeight: 44)
    }

    /// Every action of the row, for VoiceOver and the context menu.
    @ViewBuilder private func actionButtons(includingTick: Bool) -> some View {
        if includingTick, row.canTick {
            Button(row.isTicked ? undoLabel : DocumentStrings.myTasksTickAction) { tick(!row.isTicked) }
        }
        if let takeOn = actions.takeOn { Button(DocumentStrings.myTasksTakeOn, action: takeOn) }
        if let release = actions.release { Button(DocumentStrings.myTasksRelease, action: release) }
        if let handOver = actions.handOver { Button(DocumentStrings.myTasksHandOver, action: handOver) }
        if let setDate = actions.setDate { Button(DocumentStrings.myTasksSetDate, action: setDate) }
        if let wait = actions.wait { Button(DocumentStrings.waitAction, action: wait) }
        if let stopWaiting = actions.stopWaiting { Button(DocumentStrings.waitStop, action: stopWaiting) }
        if let snooze = actions.snooze { Button(DocumentStrings.snoozeAction, action: snooze) }
        if let unsnooze = actions.unsnooze { Button(DocumentStrings.snoozeStop, action: unsnooze) }
        if let openLetter = actions.openLetter { Button(DocumentStrings.myTasksOpenLetter, action: openLetter) }
    }
}
#endif
