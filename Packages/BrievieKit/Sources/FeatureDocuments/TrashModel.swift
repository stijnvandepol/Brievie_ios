import BrievieCore
import Foundation
import Observation

/// The Prullenbak screen: the letters the server keeps in the trash, how long each one stays, and "Terugzetten"
/// for a member or admin. Deleting for good and emptying the trash are done in the web (session only).
@MainActor
@Observable
public final class TrashModel {
    public enum State: Equatable, Sendable {
        case loading
        case loaded
        case failed(message: String)
    }

    /// One trashed letter as the screen shows it. Rows do not open a letter: the server answers 404 on a read.
    public struct Row: Identifiable, Equatable, Sendable {
        public let id: UUID
        /// The sender, else "Onbekende afzender".
        public let title: String
        /// Kind and letter date ("Factuur · 3 november 2026"); `nil` when the letter has neither.
        public let detail: String?
        /// "Verwijderd op 9 november 2026 door Anna".
        public let deletedLine: String
        /// "Nog 12 dagen", or "Wordt vandaag gewist".
        public let daysLeftLine: String
        /// VoiceOver's label of "Terugzetten": "Terugzetten: CAK".
        public let restoreLabel: String
    }

    public private(set) var state: State = .loading
    public private(set) var rows: [Row] = []
    /// What the trash is for, with the server's retention.
    public private(set) var intro = String(format: DocumentStrings.trashIntroFormat, 30)
    /// Under the list: removing for good is done in the web.
    public let webOnlyNote = DocumentStrings.trashWebOnly
    /// The server lists only the newest letters: says how many are shown. `nil` when all are.
    public private(set) var capNote: String?
    /// "De brief is teruggezet.", or why a restore did not work.
    public private(set) var notice: String?
    /// Members and admins restore; a viewer only reads.
    public let canRestore: Bool

    private let documents: WorkspaceDocuments
    private let clock: TodayClock
    private let locale: Locale
    private let onRestored: @MainActor (UUID) -> Void
    private let onRevoked: @MainActor () -> Void
    private let onMissingPairing: @MainActor () -> Void
    @ObservationIgnored private var restoring: Set<UUID> = []

    /// - Parameter locale: the language of the dates; the user's own by default.
    public init(
        documents: WorkspaceDocuments,
        canRestore: Bool,
        clock: TodayClock = .system,
        locale: Locale = .autoupdatingCurrent,
        onRestored: @escaping @MainActor (UUID) -> Void,
        onRevoked: @escaping @MainActor () -> Void,
        onMissingPairing: @escaping @MainActor () -> Void
    ) {
        self.documents = documents
        self.canRestore = canRestore
        self.clock = clock
        self.locale = locale
        self.onRestored = onRestored
        self.onRevoked = onRevoked
        self.onMissingPairing = onMissingPairing
    }

    /// Loads the trash; a list on screen stays when the server cannot be reached.
    public func load() async {
        do {
            let list = try await documents.trashList()
            rows = list.items.map(row(for:))
            intro = String(format: DocumentStrings.trashIntroFormat, list.retentionDays)
            capNote = list.total > list.items.count
                ? String(format: DocumentStrings.trashCapFormat, list.items.count) : nil
            state = .loaded
        } catch {
            handle(error) { error in
                if state != .loaded { state = .failed(message: DocumentsModel.message(for: error)) }
            }
        }
    }

    /// "Terugzetten": the letter leaves the trash and the list; the post list loads again.
    public func restore(_ id: UUID) async {
        guard canRestore, !restoring.contains(id) else { return }
        restoring.insert(id)
        defer { restoring.remove(id) }
        notice = nil
        do {
            _ = try await documents.restore(id)
            rows.removeAll { $0.id == id }
            notice = DocumentStrings.trashRestored
            onRestored(id)
        } catch {
            handle(error) { notice = DocumentsModel.message(for: $0) }
        }
    }

    /// Calendar days from today to the day of `purgeAfter`, both in the clock's time zone (0 or less: today).
    public static func daysLeft(until purgeAfter: Date, clock: TodayClock) -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = clock.timeZone()
        let today = calendar.startOfDay(for: clock.now())
        let purgeDay = calendar.startOfDay(for: purgeAfter)
        return calendar.dateComponents([.day], from: today, to: purgeDay).day ?? 0
    }

    // MARK: - Private

    private func row(for trashed: TrashedDocument) -> Row {
        let summary = trashed.summary
        let title = summary.sender.isEmpty ? DocumentStrings.unknownSender : summary.sender
        let kind = summary.documentType.isEmpty ? nil : DocumentTypes.documentTypeLabel(summary.documentType)
        let parts = [kind, summary.letterDate.map { $0.display(locale: locale) }].compactMap(\.self)
        let day = trashed.trashedAt.formatted(
            Date.FormatStyle(date: .long, time: .omitted, locale: locale, timeZone: clock.timeZone())
        )
        let days = Self.daysLeft(until: trashed.purgeAfter, clock: clock)
        return Row(
            id: trashed.id, title: title, detail: parts.isEmpty ? nil : parts.joined(separator: " · "),
            deletedLine: trashed.trashedByName.isEmpty
                ? String(format: DocumentStrings.trashDeletedFormat, day)
                : String(format: DocumentStrings.trashDeletedByFormat, day, trashed.trashedByName),
            daysLeftLine: days <= 0 ? DocumentStrings.trashErasedToday : DocumentStrings.trashDaysLeft(days),
            restoreLabel: String(format: DocumentStrings.trashRestoreLabelFormat, title)
        )
    }

    private func handle(_ error: DocumentsError, otherwise: (DocumentsError) -> Void) {
        switch error {
        case .revoked: onRevoked()
        case .missingPairing: onMissingPairing()
        case .cancelled: break
        default: otherwise(error)
        }
    }
}
