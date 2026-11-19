import BrievieCore

/// The Dutch explanation of a failed pairing, shared by the QR screen and the link sheet.
enum PairingFailure {
    /// The message, and whether trying the same pairing again is worth it (the server was not reachable or busy).
    /// `nil` for `.cancelled`: nothing went wrong that the user needs to read.
    static func describe(_ error: PairingError) -> (message: String, canRetry: Bool)? {
        switch error {
        case .noServerReachable: (PairingStrings.unreachable, true)
        case .serverNotVerified: (PairingStrings.notVerified, false)
        case .invalidCode: (PairingStrings.invalidCode, false)
        case .connectionLostWhilePairing: (PairingStrings.connectionLost, false)
        case .tooManyAttempts: (PairingStrings.tooManyAttempts, true)
        case .incompatibleServer: (PairingStrings.incompatible, false)
        case .cancelled: nil
        // The associated value is diagnostic only and never shown.
        case .failed: (PairingStrings.generic, false)
        }
    }
}
