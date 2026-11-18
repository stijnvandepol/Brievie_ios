import BrievieCore
import Foundation
import Observation

/// Drives the sheet behind a `brievie://server` link: a refusal, or the server's address and a field for the
/// pairing code.
///
/// When a link arrives (unpaired), the sheet asks one question and contacts nothing. Only the user's "Server zoeken"
/// finds the server (`PairingService.locate(_:)`: CA pin and health, as on the QR path; nothing derived from a code
/// exists yet) and fixes that one address. Then the sheet shows it and asks for the code, and the challenge and
/// proof go to that address and nowhere else. The typed code never leaves the phone
/// (`PairingService.pair(link:at:code:deviceName:)`).
@MainActor
@Observable
public final class ServerLinkModel {
    public enum NoticeKind: Equatable, Sendable {
        case error
        case warning
    }

    public enum Presentation: Equatable {
        /// A bad link, a newer link version, an app that is already paired, or a server that could not be found:
        /// one sentence and "Sluit".
        case notice(String, kind: NoticeKind)
        /// A link arrived; nothing has been contacted. One question and "Server zoeken".
        case question
        /// Looking for the server the link names; no code field yet.
        case searching
        /// The address the proof will go to, the last failure, and whether pairing runs.
        case offer(address: String, failure: String?, isPairing: Bool)
    }

    public private(set) var presentation: Presentation?
    /// What the user typed. Kept while the offer is open (the user may switch to Safari to read the code); cleared
    /// when the offer closes, after pairing, and when the code may be spent or was refused.
    public var code = ""

    public var canSubmit: Bool {
        guard case .offer(_, _, isPairing: false) = presentation, link != nil, located != nil else { return false }
        return PairingCode(typed: code) != nil
    }

    /// The code field is on screen: the app switcher's snapshot must not show what is typed in it.
    public var asksForCode: Bool {
        if case .offer = presentation { true } else { false }
    }

    private var isPairing: Bool {
        if case .offer(_, _, isPairing: true) = presentation { true } else { false }
    }

    private let service: PairingService
    private let deviceName: @MainActor () -> String
    private let onPaired: @MainActor (ServerConnection) -> Void
    /// The link of the open sheet. Not secret, but never shown: the sheet shows the located address only.
    private var link: ServerLink?
    /// The one address this link pairs with, fixed before the code was asked.
    private var located: LocatedServer?
    /// Counts sheets; a search that ends after its sheet was closed or replaced changes nothing.
    private var generation = 0
    @ObservationIgnored private(set) var searchTask: Task<Void, Never>?
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

    /// A link the system handed to the app. Ignored while a pairing runs; the latest link replaces an open sheet.
    public func receive(_ url: URL, appState: AppModel.State) {
        guard !isPairing else { return }
        close()
        switch appState {
        case .locked:
            // Nothing shows above the lock and nothing is kept: the user taps the link again after unlocking.
            return
        case .ready:
            presentation = .notice(PairingStrings.linkAlreadyPaired, kind: .warning)
        case .unpaired:
            do throws(ServerLinkError) {
                link = try ServerLink.parse(url)
                // Nothing is contacted until the user taps "Server zoeken" (`findServer()`).
                presentation = .question
            } catch .unsupportedVersion {
                presentation = .notice(PairingStrings.linkUnsupportedVersion, kind: .error)
            } catch {
                presentation = .notice(PairingStrings.linkInvalid, kind: .error)
            }
        }
    }

    /// The user tapped "Server zoeken": only now does the app contact the addresses the link names (CA and health,
    /// nothing derived from a code). Ignored unless the question is on screen.
    public func findServer() {
        guard presentation == .question, let link else { return }
        presentation = .searching
        let current = generation
        searchTask = Task { await search(link, generation: current) }
    }

    /// The app locked, or got paired another way: everything that is not pairing closes.
    public func appStateChanged(_ state: AppModel.State) {
        guard !isPairing else { return }
        switch state {
        case .locked, .ready: close()
        case .unpaired: break
        }
    }

    /// Starts pairing with the typed code at the located address; ignored unless `canSubmit` (so a double tap
    /// pairs once).
    public func submit() {
        guard canSubmit, let link, let located, let typed = PairingCode(typed: code) else { return }
        let address = located.displayAddress
        presentation = .offer(address: address, failure: nil, isPairing: true)
        let name = deviceName().trimmingCharacters(in: .whitespacesAndNewlines)
        let deviceName = name.isEmpty ? "iPhone" : name
        pairingTask = Task {
            await pair(link, at: located, code: typed, address: address, deviceName: deviceName)
        }
    }

    /// The user closed the sheet; ignored while pairing.
    public func dismiss() {
        guard !isPairing else { return }
        close()
    }

    private func close() {
        generation += 1
        searchTask?.cancel()
        searchTask = nil
        presentation = nil
        link = nil
        located = nil
        code = ""
    }

    private func search(_ link: ServerLink, generation current: Int) async {
        let result: Result<LocatedServer, PairingError>
        do {
            result = .success(try await service.locate(link))
        } catch {
            result = .failure(error)
        }
        guard current == generation else { return }
        switch result {
        case let .success(server):
            located = server
            presentation = .offer(address: server.displayAddress, failure: nil, isPairing: false)
        case .failure(.cancelled):
            close()
        case let .failure(error):
            self.link = nil
            presentation = .notice(PairingFailure.describe(error)?.message ?? PairingStrings.generic, kind: .error)
        }
    }

    private func pair(
        _ link: ServerLink, at located: LocatedServer, code: PairingCode, address: String, deviceName: String
    ) async {
        do {
            let connection = try await service.pair(link: link, at: located, code: code, deviceName: deviceName)
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
