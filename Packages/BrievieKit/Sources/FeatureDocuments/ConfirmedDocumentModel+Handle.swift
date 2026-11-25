import BrievieCore
import Foundation

/// "Brief afhandelen" (host PR #50): the sheet names the open tasks it ticks off and needs a tick for a payment.
/// The server checks that the tasks are still exactly these; if not, the sheet shows the new ones.
extension ConfirmedDocumentModel {
    public struct HandleSheet: Identifiable, Equatable, Sendable {
        public let taskIDs: [UUID]
        public let taskTitles: [String]
        /// A payment is among the tasks: "De betaling is gedaan of geregeld" must be ticked.
        public let needsPayment: Bool

        public var id: [UUID] { taskIDs }
    }

    /// The letter's status under its title; `nil` from a server without letter status.
    public var letterBadge: LetterBadge? { LetterStatusWords.badge(for: detail.summary) }

    /// A member may handle a checked letter that is not handled yet.
    public var canHandle: Bool {
        canEdit && [.open, .waiting].contains(detail.summary.letterStatus)
    }

    public func startHandling() {
        guard canHandle else { return }
        handleError = nil
        handleSheet = Self.sheet(for: tasks)
    }

    public func closeHandleSheet() {
        handleSheet = nil
        handleError = nil
    }

    /// Sends exactly the tasks the sheet showed. 409 `tasks_changed`: the letter loads again and the sheet shows
    /// its tasks now, with the reason.
    public func handle(paymentsConfirmed: Bool) async {
        guard let sheet = handleSheet else { return }
        handleError = nil
        do {
            let answer = try await documents.handleDocument(
                detail.summary.id, taskIDs: sheet.taskIDs, paymentsConfirmed: paymentsConfirmed
            )
            show(answer)
            handleSheet = nil
            onTasksChanged?()
        } catch .tasksChanged {
            if let fresh = try? await documents.detail(detail.summary.id) {
                show(fresh)
            }
            handleSheet = Self.sheet(for: tasks)
            handleError = DocumentStrings.errorTasksChanged
        } catch {
            handleError = switch error {
            case .paymentNotConfirmed: DocumentStrings.errorPaymentNotConfirmed
            case .notReviewed: DocumentStrings.errorNotReviewed
            default: DocumentsModel.message(for: error)
            }
        }
    }

    static func sheet(for tasks: [ConfirmedTask]) -> HandleSheet {
        let open = tasks.filter { !$0.isDone }
        return HandleSheet(
            taskIDs: open.map(\.id), taskTitles: open.map(\.description),
            needsPayment: open.contains { $0.type == "pay" }
        )
    }
}
