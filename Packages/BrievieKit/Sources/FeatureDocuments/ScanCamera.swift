import Foundation
#if os(iOS)
import AVFoundation
#endif

/// The camera permission as the scan button needs it.
public enum ScanCameraStatus: Sendable, Equatable {
    /// The user has not been asked yet.
    case notDetermined
    case allowed
    /// The user said no: Settings can change that.
    case denied
    /// The device forbids camera use (Screen Time, MDM): the app's Settings cannot change it.
    case restricted
}

/// The camera permission behind a seam, so that the documents model can be tested.
@MainActor
public protocol ScanCameraAccess {
    func status() -> ScanCameraStatus
    /// Shows the system permission prompt (once; afterwards it answers at once). `true` when access was granted.
    func requestAccess() async -> Bool
}

#if os(iOS)
/// `ScanCameraAccess` over AVFoundation.
public struct LiveScanCameraAccess: ScanCameraAccess {
    public init() {}

    public func status() -> ScanCameraStatus {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .notDetermined: .notDetermined
        case .authorized: .allowed
        case .restricted: .restricted
        case .denied: .denied
        @unknown default: .denied
        }
    }

    public func requestAccess() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .video)
    }
}
#endif
