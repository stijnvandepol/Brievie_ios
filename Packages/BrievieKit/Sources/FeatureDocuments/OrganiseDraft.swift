import BrievieCore
import Foundation

/// On whose name a letter is and which labels it gets, as the user is about to confirm it. Starts with what
/// is on the document already (an automatic rule may have put it there) plus the proposals the server ticks
/// from the start; every other proposal stays open until the user adds it.
public struct OrganiseDraft: Equatable, Sendable {
    public var addresseeIDs: Set<UUID>
    public var labelIDs: Set<UUID>
    /// The server's open proposals for this letter, as they were when the review started.
    public let suggestions: [Suggestion]

    public init() {
        addresseeIDs = []
        labelIDs = []
        suggestions = []
    }

    public init(detail: DocumentDetail) {
        suggestions = detail.suggestions
        let preselected = detail.suggestions.filter(\.isPreselected)
        addresseeIDs = Set(detail.summary.addresseeIDs)
            .union(preselected.filter { $0.action == .addAddressee }.map(\.targetID))
        labelIDs = Set(detail.summary.labelIDs).union(preselected.filter { $0.action == .addLabel }.map(\.targetID))
    }

    /// The proposals of this kind the user has not taken (yet).
    public func openSuggestions(for action: SuggestionAction) -> [Suggestion] {
        suggestions.filter { $0.action == action && !isChosen($0) }
    }

    /// Takes a proposal, or puts it back among the open ones.
    public mutating func toggle(_ suggestion: Suggestion) {
        switch suggestion.action {
        case .addAddressee:
            if addresseeIDs.remove(suggestion.targetID) == nil { addresseeIDs.insert(suggestion.targetID) }
        case .addLabel:
            if labelIDs.remove(suggestion.targetID) == nil { labelIDs.insert(suggestion.targetID) }
        case .unknown:
            break
        }
    }

    public mutating func setAddressees(_ ids: Set<UUID>) {
        addresseeIDs = ids
    }

    public mutating func setLabels(_ ids: Set<UUID>) {
        labelIDs = ids
    }

    /// The proposal a chosen person came from, for the line under its chip; `nil` when not chosen or chosen
    /// by hand (or already on the document).
    public func origin(ofAddressee id: UUID) -> Suggestion? {
        guard addresseeIDs.contains(id) else { return nil }
        return suggestions.first { $0.action == .addAddressee && $0.targetID == id }
    }

    /// The proposal a chosen label came from; `nil` when not chosen or chosen by hand.
    public func origin(ofLabel id: UUID) -> Suggestion? {
        guard labelIDs.contains(id) else { return nil }
        return suggestions.first { $0.action == .addLabel && $0.targetID == id }
    }

    private func isChosen(_ suggestion: Suggestion) -> Bool {
        switch suggestion.action {
        case .addAddressee: addresseeIDs.contains(suggestion.targetID)
        case .addLabel: labelIDs.contains(suggestion.targetID)
        case .unknown: false
        }
    }
}
