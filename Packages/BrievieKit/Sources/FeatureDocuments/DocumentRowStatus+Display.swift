import Foundation

extension DocumentsModel.RowStatus {
    /// Short Dutch label; the meaning never rests on colour or the icon alone.
    public var label: String {
        switch self {
        case .waitingForUpload: DocumentStrings.statusWaiting
        case .uploading: DocumentStrings.statusUploading
        case .uploadFailed: DocumentStrings.statusUploadFailed
        case .processing: DocumentStrings.statusProcessing
        case .needsReview: DocumentStrings.statusNeedsReview
        case .done: DocumentStrings.statusDone
        case .failed: DocumentStrings.statusFailed
        }
    }

    public var iconName: String {
        switch self {
        case .waitingForUpload: "clock"
        case .uploading: "arrow.up.circle"
        case .uploadFailed, .failed: "exclamationmark.circle.fill"
        case .processing: "gearshape"
        case .needsReview: "exclamationmark.triangle.fill"
        case .done: "checkmark.circle.fill"
        }
    }

    /// The scan has not reached the server yet and can be taken back, also while it is being sent.
    public var canDelete: Bool {
        switch self {
        case .waitingForUpload, .uploading, .uploadFailed: true
        case .processing, .needsReview, .done, .failed: false
        }
    }

    public var canRetryUpload: Bool {
        if case let .uploadFailed(_, canRetry) = self { return canRetry }
        return false
    }
}
