import BrievieCore
import Foundation
import Observation

/// "Labels" under Meer: the workspace's labels, each opening the letters that carry it. Labels are made and
/// changed on the website.
@MainActor
@Observable
public final class LabelsModel {
    public enum State: Equatable, Sendable {
        case loading
        case loaded
        case failed(message: String)
    }

    public private(set) var state: State = .loading
    public private(set) var labels: [DocumentLabel] = []

    private let documents: WorkspaceDocuments
    private let onRevoked: @MainActor () -> Void
    private let onMissingPairing: @MainActor () -> Void

    public init(
        documents: WorkspaceDocuments, onRevoked: @escaping @MainActor () -> Void,
        onMissingPairing: @escaping @MainActor () -> Void
    ) {
        self.documents = documents
        self.onRevoked = onRevoked
        self.onMissingPairing = onMissingPairing
    }

    public func load() async {
        do {
            labels = try await documents.labels()
            state = .loaded
        } catch {
            switch error {
            case .revoked: onRevoked()
            case .missingPairing: onMissingPairing()
            case .cancelled: break
            default:
                if state != .loaded { state = .failed(message: DocumentsModel.message(for: error)) }
            }
        }
    }
}
