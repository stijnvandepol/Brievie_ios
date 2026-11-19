import Foundation

extension DocumentsModel.RowStatus {
    /// Short Dutch label, in the words of the web ("Controleren", "Naam kiezen", "Bezig…", "Klaar"); the meaning
    /// never rests on colour or the icon alone.
    public var label: String {
        switch self {
        case .waitingForUpload: DocumentStrings.statusWaiting
        case .uploading: DocumentStrings.statusUploading
        case .uploadFailed: DocumentStrings.statusUploadFailed
        case .processing: DocumentStrings.statusProcessing
        case .needsReview, .failed: DocumentStrings.statusNeedsReview
        case .needsName: DocumentStrings.statusNeedsName
        case .done: DocumentStrings.statusDone
        }
    }

    /// A line under the label: why, or that there is nothing to do; `nil` when the label says it all.
    public var note: String? {
        switch self {
        case let .uploadFailed(message, _): message
        case .processing: DocumentStrings.noteProcessing
        case .failed: DocumentStrings.noteFailed
        case .waitingForUpload, .uploading, .needsReview, .needsName, .done: nil
        }
    }

    public var iconName: String {
        switch self {
        case .waitingForUpload: "clock"
        case .uploading: "arrow.up.circle"
        case .uploadFailed: "exclamationmark.icloud.fill"
        case .failed: "exclamationmark.circle.fill"
        case .processing: "hourglass"
        case .needsReview: "exclamationmark.triangle.fill"
        case .needsName: "person.crop.circle.badge.questionmark"
        case .done: "checkmark.circle.fill"
        }
    }

    /// The scan has not reached the server yet and can be taken back, also while it is being sent.
    public var canDelete: Bool {
        switch self {
        case .waitingForUpload, .uploading, .uploadFailed: true
        case .processing, .needsReview, .failed, .needsName, .done: false
        }
    }

    public var canRetryUpload: Bool {
        if case let .uploadFailed(_, canRetry) = self { return canRetry }
        return false
    }
}
