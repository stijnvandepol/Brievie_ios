import BrievieCore
import Foundation

// "Dubbel?" in "Te doen": the open pairs, and what the post list says after a choice on the compare screen.
extension DocumentsModel {
    /// One pair in the group "Dubbel?": both letters and how alike they are. Opens the compare screen.
    public struct DuplicateRow: Identifiable, Equatable, Sendable {
        /// The pair's id.
        public let id: UUID
        /// "Gemeente Voorbeelddorp, 3 november 2026"; without a letter date, when it was scanned.
        public let first: String
        public let second: String
        /// "Lijkt op elkaar voor 92%".
        public let similarity: String

        /// What VoiceOver reads for the row: both letters, then how alike they are.
        public var accessibilityLabel: String {
            [first, second, similarity].joined(separator: ". ")
        }
    }

    /// The pairs of "Te doen", asked once per whole load (never on the refresh tick) and only when the server
    /// counts open pairs: a server without them is never asked. A failure leaves the group out; the rest of
    /// "Te doen" stays.
    func loadDuplicates() async {
        guard scope == .inbox, state == .loaded, pairCount > 0 else {
            if scope != .inbox || pairCount == 0 { duplicates = [] }
            return
        }
        latestPairLoad += 1
        let load = latestPairLoad
        do {
            let pairs = try await documents.duplicates()
            // A newer load may have answered first: an older list never lands last.
            guard scope == .inbox, load == latestPairLoad else { return }
            duplicates = pairs.map(duplicateRow(for:))
        } catch .revoked {
            onRevoked()
        } catch .missingPairing {
            onMissingPairing()
        } catch .cancelled {
            return
        } catch {
            if scope == .inbox, load == latestPairLoad { duplicates = [] }
        }
    }

    /// "Het zijn twee brieven" was answered: say so in "Te doen" and load it without the pair.
    public func didDismissDuplicate() async {
        duplicateNotice = DocumentStrings.duplicateDismissed
        await load()
    }

    /// "Samenvoegen" was answered: the other letter is in the trash, so the same undo as after "Verwijderen" (which
    /// also lets the calendar follow: a twin task may be completed and the other letter's tasks left).
    public func didMerge(trashed otherID: UUID) async {
        await didTrash(otherID)
    }

    /// The pair was decided on another device meanwhile: say so and load "Te doen" again.
    public func didFindPairDecided() async {
        duplicateNotice = DocumentStrings.duplicateDecided
        await load()
    }

    public func closeDuplicateNotice() {
        duplicateNotice = nil
    }

    // MARK: - Private

    private func duplicateRow(for pair: DuplicatePair) -> DuplicateRow {
        DuplicateRow(
            id: pair.id, first: pairLine(pair.first), second: pairLine(pair.second),
            similarity: String(format: DocumentStrings.duplicateSimilarityFormat, pair.similarity)
        )
    }

    /// "<sender>, <letter date>"; "Onbekende afzender" without a sender, "Gescand op …" without a letter date.
    private func pairLine(_ letter: DocumentSummary) -> String {
        let sender = letter.sender.isEmpty ? DocumentStrings.unknownSender : letter.sender
        let day = letter.letterDate?.display(locale: locale) ?? String(
            format: DocumentStrings.duplicateScannedFormat,
            letter.createdAt.formatted(Date.FormatStyle(date: .long, time: .omitted, locale: locale))
        )
        return "\(sender), \(day)"
    }
}
