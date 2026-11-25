import BrievieCore
import Foundation

/// A letter's status in words (host PR #50): "Nieuw", "Openstaand", "Wacht op reactie tot 3 dec", "Afgehandeld",
/// and "Te laat" next to it. A server without letter status sends none: then nothing shows.
public struct LetterBadge: Equatable, Sendable {
    public let status: LetterStatus
    public let text: String
    public let isOverdue: Bool

    /// What VoiceOver reads: the status, and "Te laat" in words.
    public var accessibilityText: String {
        isOverdue ? "\(text), \(DocumentStrings.letterStatusOverdue)" : text
    }
}

enum LetterStatusWords {
    static func badge(for document: DocumentSummary, locale: Locale = .autoupdatingCurrent) -> LetterBadge? {
        let text: String
        switch document.letterStatus {
        case .new: text = DocumentStrings.letterStatusNew
        case .open: text = DocumentStrings.letterStatusOpen
        case .waiting:
            text = document.waitingUntil.map {
                String(format: DocumentStrings.letterStatusWaitingUntilFormat, TaskWords.day($0, locale: locale))
            } ?? DocumentStrings.letterStatusWaiting
        case .handled: text = DocumentStrings.letterStatusHandled
        case .none, .unknown: return nil
        }
        return LetterBadge(status: document.letterStatus, text: text, isOverdue: document.isOverdue)
    }
}
