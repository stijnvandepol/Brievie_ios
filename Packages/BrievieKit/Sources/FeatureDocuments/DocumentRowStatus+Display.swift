import Foundation

extension DocumentsModel {
    /// What a row needs, in the words of the web: "Controleren", "Naam kiezen", "Bezig…", "Klaar"; a scan still
    /// on the phone says where its upload stands.
    public enum RowStatus: Equatable, Sendable {
        case waitingForUpload
        case uploading(progress: Double)
        /// `canRetry` is false for a scan that belongs to another server: it can only be deleted.
        case uploadFailed(message: String, canRetry: Bool = true)
        /// "Bezig…": the server is reading the letter; nothing to do yet.
        case processing
        /// "Controleren".
        case needsReview
        /// "Controleren" too: the server could not read the letter, so the person fills it in.
        case failed
        /// "Naam kiezen": read, but on nobody's name.
        case needsName
        case done

        /// Something will change by itself: keep refreshing. The same rows close "Inbox".
        var isMoving: Bool { isUnderway }

        /// On its way, nothing for the person to do: an upload that is waiting or running, a letter being read.
        var isUnderway: Bool {
            switch self {
            case .waitingForUpload, .uploading, .processing: true
            case .uploadFailed, .needsReview, .failed, .needsName, .done: false
            }
        }
    }
}

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
