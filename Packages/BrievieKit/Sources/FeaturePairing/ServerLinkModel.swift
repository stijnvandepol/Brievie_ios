import BrievieCore
import Foundation
import Observation

/// Drives the sheet behind a `brievie://server` link: a refusal, or the server's address and a field for the
/// pairing code. Receiving a link contacts nothing and stores nothing; only the user's "Koppel" starts pairing,
/// and then the typed code never leaves the phone (`PairingService.pair(link:code:deviceName:)`).
@MainActor
@Observable
public final class ServerLinkModel {
    public enum Presentation: Equatable {
        /// A bad link, a newer link version, or an app that is already paired: one sentence and "Sluit".
        case notice(String)
        /// The address the app will contact, the last failure, and whether pairing runs.
        case offer(address: String, failure: String?, isPairing: Bool)
    }

    public private(set) var presentation: Presentation?
    /// What the user typed. Kept while the offer is open (the user may switch to Safari to read the code); cleared
    /// when the offer closes, after pairing, and when the code may be spent or was refused.
    public var code = ""

    public var canSubmit: Bool {
        guard case .offer(_, _, isPairing: false) = presentation, link != nil else { return false }
        return PairingCode(typed: code) != nil
    }

    private var isPairing: Bool {
        if case .offer(_, _, isPairing: true) = presentation { true } else { false }
    }

    private let service: PairingService
    private let deviceName: @MainActor () -> String
    private let onPaired: @MainActor (ServerConnection) -> Void
    /// The link of the open offer. Not secret, but never shown: the sheet shows `displayAddress` only.
    private var link: ServerLink?
    /// Owned by the model, so it survives the sheet going away: once the server accepted the proof, the pairing
    /// is stored and reported whatever the view does.
    @ObservationIgnored private(set) var pairingTask: Task<Void, Never>?

    /// - Parameters:
    ///   - deviceName: the name the server shows for this device.
    ///   - onPaired: called with the stored connection, also when the task was cancelled after the server accepted.
    public init(
        service: PairingService,
        deviceName: @escaping @MainActor () -> String,
        onPaired: @escaping @MainActor (ServerConnection) -> Void
    ) {
        self.service = service
        self.deviceName = deviceName
        self.onPaired = onPaired
    }

    /// A link the system handed to the app. Ignored while a pairing runs; the latest link replaces an open offer.
    public func receive(_ url: URL, appState: AppModel.State) {
        guard !isPairing else { return }
        close()
        switch appState {
        case .locked:
            // Nothing shows above the lock and nothing is kept: the user taps the link again after unlocking.
            return
        case .ready:
            presentation = .notice(PairingStrings.linkAlreadyPaired)
        case .unpaired:
            do throws(ServerLinkError) {
                let parsed = try ServerLink.parse(url)
                link = parsed
                presentation = .offer(address: parsed.displayAddress, failure: nil, isPairing: false)
            } catch .unsupportedVersion {
                presentation = .notice(PairingStrings.linkUnsupportedVersion)
            } catch {
                presentation = .notice(PairingStrings.linkInvalid)
            }
        }
    }

    /// The app locked, or got paired another way: everything that is not pairing closes.
    public func appStateChanged(_ state: AppModel.State) {
        guard !isPairing else { return }
        switch state {
        case .locked, .ready: close()
        case .unpaired: break
        }
    }

    /// Starts pairing with the typed code; ignored unless `canSubmit` (so a double tap pairs once).
    public func submit() {
        guard canSubmit, let link, let typed = PairingCode(typed: code), case let .offer(address, _, _) = presentation
        else {
            return
        }
        presentation = .offer(address: address, failure: nil, isPairing: true)
        let name = deviceName().trimmingCharacters(in: .whitespacesAndNewlines)
        let deviceName = name.isEmpty ? "iPhone" : name
        pairingTask = Task { await pair(link, code: typed, address: address, deviceName: deviceName) }
    }

    /// The user closed the sheet; ignored while pairing.
    public func dismiss() {
        guard !isPairing else { return }
        close()
    }

    private func close() {
        presentation = nil
        link = nil
        code = ""
    }

    private func pair(_ link: ServerLink, code: PairingCode, address: String, deviceName: String) async {
        do {
            let connection = try await service.pair(link: link, code: code, deviceName: deviceName)
            close()
            onPaired(connection)
        } catch {
            switch error {
            // The code was refused or may be spent: the field is cleared for a new one.
            case .invalidCode, .connectionLostWhilePairing: self.code = ""
            default: break
            }
            presentation = .offer(address: address, failure: Self.message(for: error), isPairing: false)
        }
    }

    private static func message(for error: PairingError) -> String? {
        if error == .invalidCode { return PairingStrings.linkInvalidCode }
        return PairingFailure.describe(error)?.message
    }
}
