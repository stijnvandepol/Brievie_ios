@testable import BrievieCore
import BrievieScan
@testable import FeatureWorkspace
import Foundation
import Synchronization
import Testing

/// A `BrievieServer` that only knows workspaces; the answer is set per URL.
final class WorkspaceServer: BrievieServer {
    private struct State {
        var urls: [URL] = []
        var tokens: [String] = []
        var revoked: [UUID] = []
        var answer: @Sendable (URL) throws -> [WorkspaceSummary] = { _ in [] }
    }

    private let state = Mutex(State())

    var urls: [URL] { state.withLock { $0.urls } }
    var tokens: [String] { state.withLock { $0.tokens } }
    var revoked: [UUID] { state.withLock { $0.revoked } }

    var answer: @Sendable (URL) throws -> [WorkspaceSummary] {
        get { state.withLock { $0.answer } }
        set { state.withLock { $0.answer = newValue } }
    }

    func workspaces(at url: URL, trust: ServerTrust, token: String) async throws -> [WorkspaceSummary] {
        let answer = state.withLock {
            $0.urls.append(url)
            $0.tokens.append(token)
            return $0.answer
        }
        return try answer(url)
    }

    func health(at url: URL, trust: ServerTrust) async throws -> String { "1.0.0" }
    func caCertificatePEM(at url: URL) async throws -> String { "" }
    func pair(at url: URL, trust: ServerTrust, code: String, deviceName: String) async throws -> PairedDevice {
        throw ServerError.other("not expected")
    }

    func revokeDevice(_ deviceID: UUID, at url: URL, trust: ServerTrust, token: String) async throws {
        state.withLock { $0.revoked.append(deviceID) }
    }
}

/// An upload queue that only holds items and can be emptied.
final class ScriptedUploadQueue: UploadQueue {
    private let queued: Mutex<[UploadItem]>

    init(count: Int) {
        queued = Mutex((0..<count).map { _ in
            UploadItem(
                id: UUID(), workspaceID: UUID(), deviceID: UUID(), createdAt: Date(), pageCount: 1,
                bodyByteCount: 10, boundary: "b", state: .waiting, attempt: 0, urlIndex: 0, nextAttemptAt: nil,
                failureCode: nil
            )
        })
    }

    func enqueue(pages: [ScannedPage], workspaceID: UUID) async throws(UploadQueueError) -> UploadItem {
        throw .writeFailed
    }

    func items() async -> [UploadItem] { queued.withLock { $0 } }
    func retry(_ id: UUID) async {}
    func delete(_ id: UUID) async { queued.withLock { $0.removeAll { $0.id == id } } }
    func removeAll() async throws { queued.withLock { $0.removeAll() } }
    func progressUpdates() async -> AsyncStream<[UUID: Double]> { AsyncStream { $0.finish() } }
    func takeRemovedUnreadableCount() async -> Int { 0 }
}

private struct NoAuthentication: DeviceAuthenticator {
    func availability() -> AuthenticationAvailability { .available }
    func authenticate(reason: String) async -> Bool { true }
}

@MainActor
@Suite struct WorkspacesModelTests {
    private let home = URL(string: "https://brievie.local")
    private let away = URL(string: "https://brievie.example.nl")
    private let server = WorkspaceServer()
    private let secrets = InMemorySecretStore()
    private let connection: ServerConnection
    private let appModel: AppModel
    private let model: WorkspacesModel
    private let uploads = ScriptedUploadQueue(count: 0)

    init() throws {
        let urls = try [#require(home), #require(away)]
        connection = ServerConnection(urls: urls, caCertificateDER: nil, deviceID: UUID(), userName: "Beheerder")
        let store = ConnectionStore(secrets: secrets)
        try store.save(connection, token: "device-token")
        appModel = AppModel(
            store: store,
            authenticator: NoAuthentication(),
            launchFlag: InMemoryLaunchFlag(hasLaunchedBefore: true),
            isProtectedDataAvailable: { true }
        )
        appModel.didPair(connection)
        model = WorkspacesModel(
            connection: connection, store: store, server: server, appModel: appModel,
            unpairing: Unpairing(server: server, uploads: uploads)
        )
    }

    private func summary(
        _ name: String, kind: WorkspaceSummary.Kind = .home, role: WorkspaceSummary.Role = .admin
    ) -> WorkspaceSummary {
        WorkspaceSummary(id: UUID(), name: name, kind: kind, role: role)
    }

    @Test func startsLoading() {
        #expect(model.state == .loading)
    }

    @Test func loadsTheWorkspacesWithTheStoredToken() async {
        let thuis = summary("Thuis")
        server.answer = { _ in [thuis] }

        await model.load()

        #expect(model.state == .loaded([
            WorkspacesModel.Row(
                id: thuis.id, name: "Thuis", kind: .home, kindLabel: "Thuis", roleLabel: "Beheerder", role: .admin
            )
        ]))
        #expect(server.tokens == ["device-token"])
    }

    @Test func anEmptyListIsLoaded() async {
        await model.load()

        #expect(model.state == .loaded([]))
    }

    @Test func unknownKindAndRoleGetNeutralLabels() async {
        let mystery = summary("Nieuw", kind: .unknown, role: .unknown)
        let member = summary("Werk", kind: .business, role: .member)
        server.answer = { _ in [mystery, member] }

        await model.load()

        #expect(model.state == .loaded([
            WorkspacesModel.Row(id: mystery.id, name: "Nieuw", kind: .unknown, kindLabel: "Werkruimte", roleLabel: nil),
            WorkspacesModel.Row(
                id: member.id, name: "Werk", kind: .business, kindLabel: "Zakelijk", roleLabel: "Lid", role: .member
            )
        ]))
    }

    // MARK: - URLs

    @Test func triesTheNextURLWhenTheFirstIsUnreachable() async {
        let home = home
        server.answer = { url in
            if url == home { throw ServerError.unreachable }
            return []
        }

        await model.load()

        #expect(server.urls == [home, away])
        #expect(model.state == .loaded([]))
    }

    @Test func nothingReachableIsAnError() async {
        server.answer = { _ in throw ServerError.unreachable }

        await model.load()

        #expect(model.state == .failed(
            message: "We kunnen je Brievie-server niet bereiken. Zit je op hetzelfde netwerk?"
        ))
        #expect(server.urls.count == 2)
    }

    @Test func aFailedLoadCanBeRetried() async {
        server.answer = { _ in throw ServerError.unreachable }
        await model.load()

        server.answer = { _ in [] }
        await model.load()

        #expect(model.state == .loaded([]))
    }

    @Test func aRefreshThatFailsKeepsTheListOnScreen() async {
        let thuis = summary("Thuis")
        server.answer = { _ in [thuis] }
        await model.load()

        server.answer = { _ in throw ServerError.unreachable }
        await model.load()

        guard case .loaded(let rows) = model.state else {
            Issue.record("Expected the list to stay, got \(model.state)")
            return
        }
        #expect(rows.map(\.name) == ["Thuis"])
    }

    @Test func diagnosticTextNeverReachesTheUser() async {
        server.answer = { _ in throw ServerError.other("http_500_secret") }

        await model.load()

        #expect(model.state == .failed(message: "Er ging iets mis. Probeer het opnieuw."))
        #expect(server.urls.count == 1)
    }

    @Test func untrustedIsReportedAsNotVerified() async {
        server.answer = { _ in throw ServerError.untrusted }

        await model.load()

        guard case .failed(let message) = model.state else {
            Issue.record("Expected a failure, got \(model.state)")
            return
        }
        #expect(message.hasPrefix("We konden niet controleren"))
    }

    @Test func aCancelledLoadShowsNoError() async {
        server.answer = { _ in throw CancellationError() }

        await model.load()

        #expect(model.state == .loading)
    }

    // MARK: - Review Focus 6: revoked

    @Test func unauthorizedSendsTheAppBackToPairing() async {
        server.answer = { _ in throw ServerError.unauthorized }

        await model.load()

        #expect(appModel.state == .unpaired(
            notice: "Dit apparaat is ontkoppeld. Koppel het opnieuw om verder te gaan."
        ))
        #expect(server.urls.count == 1)
        #expect(secrets.read(.deviceToken) == nil)
    }

    @Test func aMissingTokenSendsTheAppBackToPairingWithTheGenericMessage() async throws {
        try ConnectionStore(secrets: secrets).clear()

        await model.load()

        #expect(appModel.state == .unpaired(notice: "Er ging iets mis. Probeer het opnieuw."))
        #expect(server.urls.isEmpty)
    }

    @Test func aStaleModelCannotWipeANewPairing() async throws {
        // The old connection's screen is still loading when a new pairing is made.
        let fresh = ServerConnection(
            urls: try [#require(home)], caCertificateDER: nil, deviceID: UUID(), userName: "Nieuw"
        )
        try ConnectionStore(secrets: secrets).save(fresh, token: "fresh-token")
        appModel.didPair(fresh)
        server.answer = { _ in throw ServerError.unauthorized }

        await model.load()

        #expect(appModel.state == .ready(fresh))
        #expect(secrets.read(.deviceToken) == Data("fresh-token".utf8))
    }

    // MARK: - lifecycle

    @Test func stoppingCancelsARetryThatIsStillRunning() async {
        server.answer = { _ in
            if Task.isCancelled { throw CancellationError() }
            return []
        }

        model.retry()
        model.stop()

        #expect(model.state == .loading)
        #expect(model.retryTask == nil)
    }

    @Test func retryLoadsAgain() async {
        server.answer = { _ in throw ServerError.unreachable }
        await model.load()
        server.answer = { _ in [] }

        model.retry()
        await model.retryTask?.value

        #expect(model.state == .loaded([]))
    }

    // MARK: - unpair

    private func model(queued: Int) -> WorkspacesModel {
        WorkspacesModel(
            connection: connection, store: ConnectionStore(secrets: secrets), server: server, appModel: appModel,
            unpairing: Unpairing(server: server, uploads: ScriptedUploadQueue(count: queued))
        )
    }

    @Test func askingToUnpairCountsTheQueueBeforeTheDialogOpens() async {
        let model = model(queued: 3)

        model.requestUnpair()
        await model.unpairCountTask?.value

        #expect(model.queuedScanCount == 3)
        #expect(model.isConfirmingUnpair)
        #expect(model.unpairMessage.contains("3 scans"))
        #expect(appModel.state == .ready(connection))
    }

    @Test func withAnEmptyQueueTheDialogDoesNotMentionScans() async {
        model.requestUnpair()
        await model.unpairCountTask?.value

        #expect(model.queuedScanCount == 0)
        #expect(model.isConfirmingUnpair)
        #expect(model.unpairMessage == WorkspaceStrings.unpairMessage)
        #expect(!model.unpairMessage.contains("scan"))
    }

    @Test func confirmingUnpairsThroughTheAppModel() async {
        model.confirmUnpair()
        await appModel.unpairTask?.value

        #expect(server.revoked == [connection.deviceID])
        #expect(appModel.state == .unpaired(notice: nil))
        #expect(secrets.read(.deviceToken) == nil)
    }

    @Test func theQueuedMessageHasASingularAndAPluralInTheCatalog() throws {
        let key = "workspaces.unpair.message.queued"
        let forms = try CatalogParity.dutchPlural(forKey: key, target: "FeatureWorkspace")
        let again = "Je kunt daarna opnieuw koppelen met een nieuwe QR-code."

        #expect(forms["one"] == "Er wacht nog %lld scan om te versturen. "
            + "Die scan wordt van deze telefoon verwijderd. " + again)
        #expect(forms["other"] == "Er wachten nog %lld scans om te versturen. "
            + "Die scans worden van deze telefoon verwijderd. " + again)
        // `swift test` does not compile catalogs: the code's default is the plural form.
        let expected = forms["other"]?.replacingOccurrences(of: "%lld", with: "2")
        #expect(WorkspaceStrings.unpairMessageQueued(2) == expected)
    }

    // MARK: - copy

    @Test func catalogAndCodeAgree() throws {
        for (key, resolved) in WorkspaceStrings.all {
            #expect(try CatalogParity.dutchValue(forKey: key, target: "FeatureWorkspace") == resolved, "\(key)")
        }
    }
}

@Suite struct WorkspaceRowRoleTests {
    @Test func rowCarriesTheRoleForWhatTheUserMayDo() {
        let member = WorkspaceSummary(id: UUID(), name: "Werk", kind: .business, role: .member)

        #expect(WorkspacesModel.Row(workspace: member).role == .member)
    }
}

@Suite struct WorkspaceRowIconTests {
    @Test func iconFollowsTheKindNotTheLabel() {
        func icon(_ kind: WorkspaceSummary.Kind) -> String {
            WorkspacesModel.Row(id: UUID(), name: "x", kind: kind, kindLabel: "anders", roleLabel: nil).iconName
        }

        #expect(icon(.home) == "house.fill")
        #expect(icon(.business) == "briefcase.fill")
        #expect(icon(.unknown) == "square.grid.2x2.fill")
    }
}

@Suite struct WorkspaceRowSubtitleTests {
    private func row(name: String, kindLabel: String, roleLabel: String?) -> WorkspacesModel.Row {
        WorkspacesModel.Row(id: UUID(), name: name, kind: .home, kindLabel: kindLabel, roleLabel: roleLabel)
    }

    @Test func kindLabelThatRepeatsTheNameIsLeftOut() {
        #expect(row(name: " thuis ", kindLabel: "Thuis", roleLabel: "Beheerder").subtitle == "Beheerder")
    }

    @Test func otherNamesKeepKindAndRole() {
        #expect(row(name: "Mijn huis", kindLabel: "Thuis", roleLabel: "Beheerder").subtitle == "Thuis · Beheerder")
        #expect(row(name: "Mijn huis", kindLabel: "Thuis", roleLabel: nil).subtitle == "Thuis")
    }
}
