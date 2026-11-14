import Foundation
#if os(iOS)
import AVFoundation
import VisionKit
#endif

/// What the pairing screen may do with the camera.
public enum CameraStatus: Sendable, Equatable {
    /// The user has not been asked yet.
    case notDetermined
    case authorized
    /// The user said no: Settings can change that.
    case denied
    /// The device restricts camera access (Screen Time, MDM): the user cannot change it in the app's Settings.
    case restricted
    /// This device cannot scan QR codes in the app (simulator, no camera).
    case unsupported
}

/// The camera permission and scanner support, behind a seam so that the pairing model can be tested.
@MainActor
public protocol CameraAccess {
    func status() -> CameraStatus
    /// Shows the system permission prompt (once; afterwards it answers at once). `true` when access was granted.
    func requestAccess() async -> Bool
}

#if os(iOS)
/// `CameraAccess` over AVFoundation and VisionKit's `DataScannerViewController`.
public struct LiveCameraAccess: CameraAccess {
    public init() {}

    public func status() -> CameraStatus {
        guard DataScannerViewController.isSupported else { return .unsupported }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .notDetermined:
            return .notDetermined
        case .authorized:
            // Authorized but still not available: the scanner cannot run on this device right now.
            return DataScannerViewController.isAvailable ? .authorized : .unsupported
        case .denied:
            return .denied
        case .restricted:
            return .restricted
        @unknown default:
            return .denied
        }
    }

    public func requestAccess() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .video)
    }
}
#endif
