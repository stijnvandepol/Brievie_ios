# iOS Fundament (fase 1a) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** An iOS app that pairs with a Brievie server by scanning the QR code from the web interface, trusts only that server's certificate authority, stores its device token in the Keychain, unlocks with Face ID, and shows the user's workspaces.

**Architecture:** A thin SwiftUI app target on top of one local Swift package (`Packages/BrievieKit`) with one target per responsibility. The API client is generated from the host's `openapi.json`; no API type is written by hand. Logic lives in `@Observable` models and plain types that are tested without UI; `BrievieAPI` and `BrievieCore` also compile for macOS so `swift test` runs in seconds.

**Tech Stack:** Swift 6 (strict concurrency), SwiftUI, iOS 18.0+, Xcode 26, XcodeGen, Swift Package Manager, swift-openapi-generator + swift-openapi-runtime + swift-openapi-urlsession, Swift Testing, SwiftLint, String Catalogs.

**Spec:** `../Brievie_host/docs/SPEC.md` (sections 11, 13, 14, 16 step 1a, 18, 19). Host contract: `../Brievie_host/docs/api/openapi.json`. Host plan: `../Brievie_host/docs/superpowers/plans/2026-11-13-host-fundament.md` (Tasks 5–7 define pairing).

## Global Constraints

- Code, comments and commits in English. All visible text in Dutch (B1, je-vorm) through `Localizable.xcstrings`; never a literal string in a view.
- Swift 6 language mode, strict concurrency complete. `async/await` only; no `DispatchQueue`, no manual threads.
- No force unwrap (`!`), `try!` or `as!` outside tests. SwiftLint clean with `force_unwrapping` enabled.
- Secrets (device token, CA certificate, server config) only in the Keychain, accessibility `afterFirstUnlockThisDeviceOnly`. Never `UserDefaults`, never a file.
- Views are dumb: they render model state and forward actions. No networking or Keychain access in a view.
- HTTPS only. No `NSAllowsArbitraryLoads`. Non-`https` URLs are rejected at parse time.
- Every screen works with VoiceOver and at the largest Dynamic Type size.
- The Xcode project is generated (`project.yml`); `*.xcodeproj` is git-ignored.
- No new dependency without a line in `docs/DECISIONS.md`.
- Bundle id `nl.stijnvdpol.brievie`; App Group `group.nl.stijnvdpol.brievie` (reserved for the share extension and widget, not used in 1a).
- Work on branch `feat/fundament`. Conventional commits. Do not push.

## Review Focus

1. The QR code is not a Brievie code (a web link, a Wi-Fi code, random text): a friendly Dutch message and the scanner keeps running; no crash, nothing stored. → Task 2.
2. The CA certificate fetched from the server does not match the fingerprint in the QR code: pairing stops, nothing is stored, the message says the server could not be verified. → Task 5.
3. The server renews its leaf certificate (same CA): the app keeps working. A certificate from a different CA, or a public CA when a private one is pinned, is refused. → Task 3.
4. The first URL in the payload is unreachable (not on the home network): the next URL is tried; if all fail the user gets a retry button and the scanned payload is kept. → Task 5.
5. Face ID is unavailable or not enrolled: fall back to the device passcode; if the device has no passcode at all, the app opens with a warning instead of locking the user out. → Task 6.
6. The server answers 401 (device revoked on the server): the app clears its secrets and returns to the pairing screen with an explanation. → Task 6.

## File Structure

```
project.yml                         # XcodeGen
Makefile                            # generate, test, lint, build, sync-api
.swiftlint.yml  .gitignore  CLAUDE.md  README.md
App/
  BrievieApp.swift                  # @main, creates AppModel, RootView
  RootView.swift                    # switches on AppModel.state
  Info.plist  Localizable.xcstrings  Assets.xcassets
Packages/BrievieKit/
  Package.swift                     # platforms: iOS 18, macOS 15
  Sources/
    BrievieAPI/                     # openapi.json, openapi-generator-config.yaml, API_VERSION, APIClient.swift
    BrievieCore/                    # PairingPayload, CertificatePin, ServerTrust, PinnedSessionDelegate,
                                    # SecretStore, ServerConnection, PairingService, AppLock, AppModel
    BrievieUI/                      # shared view pieces (ErrorBanner, PrimaryButton)
    FeaturePairing/                 # PairingModel, PairingView, QRScannerView
    FeatureWorkspace/               # WorkspacesModel, WorkspacesView
  Tests/
    BrievieCoreTests/  FeaturePairingTests/  FeatureWorkspaceTests/
    Fixtures/                       # make-certs.sh + generated test certificates
docs/DECISIONS.md
.github/workflows/ci.yml
```

---

### Task 1: Project skeleton and tooling

**Files:**
- Create: `project.yml`, `Makefile`, `.swiftlint.yml`, `.gitignore`, `CLAUDE.md`, `README.md`, `docs/DECISIONS.md`, `App/{BrievieApp.swift,RootView.swift,Info.plist,Localizable.xcstrings}`, `Packages/BrievieKit/Package.swift`, one placeholder source + test per target, `.github/workflows/ci.yml`

**Interfaces:**
- Produces: Make targets `make generate` (xcodegen), `make test` (`swift test --package-path Packages/BrievieKit`), `make lint` (`swiftlint --strict`), `make build` (xcodebuild for the iPhone 17 simulator with `-skipPackagePluginValidation`), `make sync-api HOST=../Brievie_host`.
- Produces: `Info.plist` keys `NSCameraUsageDescription` ("Brievie gebruikt de camera om de koppelcode en je post te scannen."), `NSFaceIDUsageDescription` ("Brievie gebruikt Face ID om je post af te schermen."), `NSLocalNetworkUsageDescription` ("Brievie zoekt je Brievie-server op je thuisnetwerk."). `ITSAppUsesNonExemptEncryption = false`.
- Source language of the String Catalog is `nl`.

- [ ] **Step 1:** `brew install xcodegen swiftlint`. Write `project.yml` (app target `Brievie`, iOS 18.0, Swift 6, depends on the `BrievieKit` products) and `Package.swift` with the five library targets and three test targets from File Structure.
- [ ] **Step 2:** Placeholder test per test target using Swift Testing (`@Test func targetBuilds() { #expect(true) }`).
- [ ] **Step 3:** Run `make generate test lint build`; expected: all succeed, the app launches in the simulator showing the text "Brievie".
- [ ] **Step 4:** CI on `macos-latest`: lint, `swift test`, simulator build. `CLAUDE.md`: pointer to the spec and this plan, the Make targets, Global Constraints in short form.
- [ ] **Step 5:** Commit `chore: project skeleton with package targets and CI`.

### Task 2: Pairing payload

**Files:**
- Create: `Sources/BrievieCore/Pairing/PairingPayload.swift`
- Test: `Tests/BrievieCoreTests/PairingPayloadTests.swift`

**Interfaces:**
- Produces:

```swift
public struct PairingPayload: Equatable, Sendable {
    public let urls: [URL]          // in server order: local first
    public let code: String         // "XXXX-XXXX"
    public let caSHA256: String?    // lower-case hex, nil when the server uses a public certificate
    public static func parse(_ qrText: String) throws(PairingPayloadError) -> PairingPayload
}
public enum PairingPayloadError: Error, Equatable {
    case notBrievie          // not JSON, or no "v"
    case unsupportedVersion  // v != 1
    case invalid             // missing fields, no urls, non-https url, malformed hash
}
```

- Wire format (from the host): `{"v":1,"urls":["https://…"],"code":"ABCD-EFGH","ca_sha256":"<64 hex>"|null}`.

- [ ] **Step 1:** Failing tests: valid payload with and without `ca_sha256`; `"https://nos.nl"` → `.notBrievie`; `"WIFI:S:thuis;;"` → `.notBrievie`; `{"v":2,…}` → `.unsupportedVersion`; an `http://` URL → `.invalid`; empty `urls` → `.invalid`; hash of 63 characters or with non-hex characters → `.invalid`; upper-case hash is normalised to lower case (Review Focus 1).
- [ ] **Step 2:** Run `make test`; FAIL. Implement. Run; PASS.
- [ ] **Step 3:** Commit `feat(core): parse the pairing QR payload`.

### Task 3: Certificate pin and server trust

**Files:**
- Create: `Sources/BrievieCore/Trust/{CertificatePin.swift,ServerTrust.swift,PinnedSessionDelegate.swift}`
- Create: `Tests/Fixtures/make-certs.sh` and its output: `ca.pem`, `leaf-a.pem`, `leaf-b.pem` (both for `localhost`, signed by `ca`), `other-ca.pem`, `other-leaf.pem`, and `ca.sha256` (from `openssl x509 -outform der | shasum -a 256`). Valid 20 years so tests do not expire.
- Test: `Tests/BrievieCoreTests/{CertificatePinTests.swift,ServerTrustTests.swift}`

**Interfaces:**
- Produces:

```swift
public enum CertificatePin {
    public static func der(fromPEM pem: String) throws(TrustError) -> Data
    public static func sha256Hex(ofDER der: Data) -> String          // lower-case hex, CryptoKit
}
public struct ServerTrust: Sendable {
    public init(caCertificateDER: Data?)                              // nil = system trust
    public func evaluate(_ trust: SecTrust, host: String) -> Bool
}
public final class PinnedSessionDelegate: NSObject, URLSessionDelegate, Sendable {
    public init(trust: ServerTrust)
}
public enum TrustError: Error, Equatable { case malformedCertificate }
```

- `evaluate` with a CA: `SecTrustSetPolicies` (SSL policy for `host`), `SecTrustSetAnchorCertificates([ca])`, `SecTrustSetAnchorCertificatesOnly(true)`, then `SecTrustEvaluateWithError`. With `nil`: default evaluation only.
- `PinnedSessionDelegate` answers `NSURLAuthenticationMethodServerTrust` with `.useCredential` when `evaluate` is true, otherwise `.cancelAuthenticationChallenge`; other challenge types get default handling.

- [ ] **Step 1:** Failing tests: `sha256Hex(der(ca.pem))` equals the content of `ca.sha256`; garbage PEM → `.malformedCertificate`; `evaluate` is true for `leaf-a` **and** `leaf-b` against `ca` (renewed leaf, Review Focus 3); false for `other-leaf` against `ca`; false for `leaf-a` with host `example.com`; with `caCertificateDER: nil`, `leaf-a` is refused (not publicly trusted). Build the `SecTrust` in tests with `SecTrustCreateWithCertificates`.
- [ ] **Step 2:** Run; FAIL. Implement. Run; PASS.
- [ ] **Step 3:** Commit `feat(core): trust only the paired server's certificate authority`.

### Task 4: Secret storage and server connection

**Files:**
- Create: `Sources/BrievieCore/Storage/{SecretStore.swift,KeychainSecretStore.swift,InMemorySecretStore.swift,ServerConnection.swift,ConnectionStore.swift}`
- Test: `Tests/BrievieCoreTests/{ConnectionStoreTests.swift,KeychainSecretStoreTests.swift}`

**Interfaces:**
- Produces:

```swift
public enum SecretKey: String, Sendable { case deviceToken, serverConnection }
public protocol SecretStore: Sendable {
    func read(_ key: SecretKey) throws -> Data?
    func write(_ data: Data, for key: SecretKey) throws
    func delete(_ key: SecretKey) throws
}
public struct ServerConnection: Codable, Equatable, Sendable {
    public let urls: [URL]
    public let caCertificateDER: Data?
    public let deviceID: UUID
    public let userName: String
}
public struct ConnectionStore: Sendable {
    public init(secrets: any SecretStore)
    public func load() throws -> (connection: ServerConnection, token: String)?
    public func save(_ connection: ServerConnection, token: String) throws
    public func clear() throws
}
```

- `KeychainSecretStore(service: String = "nl.stijnvdpol.brievie")`: generic password items, `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, not synchronisable.
- `load()` returns `nil` when either item is missing, and clears the leftover item (never a half-paired state).

- [ ] **Step 1:** Failing tests against `InMemorySecretStore`: save → load round-trip; clear → `nil`; only the token present → `nil` and the token is gone afterwards. One Keychain test (round-trip, overwrite, delete) guarded to run on the simulator only.
- [ ] **Step 2:** Run; FAIL. Implement. Run; PASS.
- [ ] **Step 3:** Commit `feat(core): keep the server connection in the Keychain`.

### Task 5: API client and pairing flow

**Depends on:** host Task 7 (a committed `docs/api/openapi.json` containing `getHealth`, `getCaCertificate`, `pairDevice`, `listWorkspaces`, `getMe`).

**Files:**
- Create: `Sources/BrievieAPI/{openapi.json,openapi-generator-config.yaml,API_VERSION,APIClient.swift}`
- Create: `Sources/BrievieCore/Pairing/{PairingService.swift,BrievieServer.swift}`
- Test: `Tests/BrievieCoreTests/PairingServiceTests.swift`

**Interfaces:**
- `make sync-api` copies the host's `openapi.json` and writes `info.version` to `API_VERSION`. The generator runs as a build plugin (`generate: [types, client]`, `accessModifier: public`).
- Produces `APIClient.make(baseURL: URL, trust: ServerTrust, token: String?) -> Client`: a generated `Client` on a `URLSession` with `PinnedSessionDelegate`, base path `/api/v1`, and a middleware that adds `Authorization: Bearer` when a token is given.
- Produces the seam the rest of the app talks to, so features never touch generated types:

```swift
public protocol BrievieServer: Sendable {
    func health(at url: URL, trust: ServerTrust) async throws -> String            // api_version
    func caCertificatePEM(at url: URL) async throws -> String                      // unauthenticated, see below
    func pair(at url: URL, trust: ServerTrust, code: String, deviceName: String) async throws -> PairedDevice
    func workspaces(at url: URL, trust: ServerTrust, token: String) async throws -> [WorkspaceSummary]
}
public struct PairedDevice: Equatable, Sendable { let deviceID: UUID; let token: String; let userName: String }
public struct WorkspaceSummary: Equatable, Sendable, Identifiable { let id: UUID; let name: String; let kind: Kind; let role: Role }
// WorkspaceSummary.Kind: home, business. WorkspaceSummary.Role: admin, member, viewer (raw values match the API).
public enum ServerError: Error, Equatable { case unreachable, untrusted, unauthorized, invalidCode, tooManyAttempts, incompatible, other(String) }

public struct PairingService: Sendable {
    public init(server: any BrievieServer, store: ConnectionStore)
    public func pair(_ payload: PairingPayload, deviceName: String) async throws(PairingError) -> ServerConnection
}
public enum PairingError: Error, Equatable { case noServerReachable, serverNotVerified, invalidCode, tooManyAttempts, incompatibleServer, failed(String) }
```

- `LiveBrievieServer` implements `BrievieServer` with the generated client and maps HTTP 401 → `.unauthorized`, 400 `pairing_code_invalid` → `.invalidCode`, 429 → `.tooManyAttempts`, connection failures → `.unreachable`, a cancelled trust challenge → `.untrusted`.
- `caCertificatePEM(at:)` is the only call made before trust exists. It uses a one-off session that accepts the server's certificate **for this request only**; the result is worthless until its fingerprint matches the QR code. Document this in a comment at the call site.
- `PairingService.pair` algorithm, per URL in order: (1) if `caSHA256 != nil`: fetch the PEM, convert to DER, compare `CertificatePin.sha256Hex` with the payload; mismatch → throw `.serverNotVerified` immediately, do not try other URLs; (2) build `ServerTrust`; (3) `health` — major version must be `1`, else `.incompatibleServer`; (4) `pair`; (5) `store.save`. `.unreachable` at step 1 or 3 moves to the next URL; all unreachable → `.noServerReachable`.

- [ ] **Step 1:** Failing tests with a `FakeBrievieServer`: happy path stores the connection and token; fingerprint mismatch → `.serverNotVerified`, store stays empty, `pair` never called (Review Focus 2); first URL unreachable, second works → connection saved with both URLs in original order (Review Focus 4); all unreachable → `.noServerReachable`; invalid code → `.invalidCode`, store empty; `api_version` `"2.0.0"` → `.incompatibleServer`; payload with `caSHA256 == nil` never calls `caCertificatePEM`.
- [ ] **Step 2:** Run; FAIL. Implement. Run; PASS. `make build` succeeds with the generator plugin.
- [ ] **Step 3:** Commit `feat(core): pair with a server through the generated API client`.

### Task 6: App state, lock, pairing and workspace screens

**Files:**
- Create: `Sources/BrievieCore/App/{AppModel.swift,AppLock.swift}`, `Sources/FeaturePairing/{PairingModel.swift,PairingView.swift,QRScannerView.swift}`, `Sources/FeatureWorkspace/{WorkspacesModel.swift,WorkspacesView.swift}`, `Sources/BrievieUI/{ErrorBanner.swift,PrimaryButton.swift}`
- Modify: `App/{BrievieApp.swift,RootView.swift,Localizable.xcstrings}`
- Test: `Tests/BrievieCoreTests/AppModelTests.swift`, `Tests/FeaturePairingTests/PairingModelTests.swift`, `Tests/FeatureWorkspaceTests/WorkspacesModelTests.swift`

**Interfaces:**
- Produces:

```swift
public protocol DeviceAuthenticator: Sendable {
    func canAuthenticate() -> Bool                         // false when the device has no passcode
    func authenticate(reason: String) async -> Bool        // LAPolicy.deviceOwnerAuthentication
}
@MainActor @Observable public final class AppModel {
    public enum State: Equatable { case unpaired(notice: String?), locked, ready(ServerConnection) }
    public private(set) var state: State
    public init(store: ConnectionStore, authenticator: any DeviceAuthenticator)
    public func start()                 // unpaired if nothing stored, else locked
    public func unlock() async          // locked -> ready on success
    public func didPair(_ connection: ServerConnection)
    public func didBecomeInactive()     // ready -> locked
    public func sessionRevoked()        // clears the store, -> unpaired(notice:)
}
```

- `PairingModel` (`@MainActor @Observable`): `phase` (`scanning`, `pairing`, `failed(message:canRetry:)`), `func scanned(_ text: String) async`, `func retry() async`, `func submitManual(_ text: String) async`. Keeps the last valid payload for `retry`.
- `QRScannerView`: `DataScannerViewController` for QR codes when `DataScannerViewController.isSupported && isAvailable`; otherwise (simulator, camera denied) a text field "Plak de koppelcode" that feeds `submitManual`. This fallback is also how the flow is tested in the simulator.
- `WorkspacesModel`: `state` (`loading`, `loaded([WorkspaceSummary])`, `failed(message:)`), `func load() async`; on `ServerError.unauthorized` it calls `AppModel.sessionRevoked()`. Tries `connection.urls` in order.
- Device name sent when pairing: `UIDevice.current.name`.
- Dutch copy (exact): not a Brievie code → "Dit is geen Brievie-code. Open in de webinterface 'App koppelen' en scan de code daar."; `.serverNotVerified` → "We konden niet controleren of dit jouw Brievie-server is. Maak een nieuwe code en probeer het opnieuw."; `.noServerReachable` → "We kunnen je Brievie-server niet bereiken. Zit je op hetzelfde netwerk?"; `.invalidCode` → "Deze code is verlopen of al gebruikt. Maak een nieuwe code."; revoked → "Dit apparaat is ontkoppeld. Koppel het opnieuw om verder te gaan."

- [ ] **Step 1:** Failing model tests: `start()` → `.unpaired(nil)` with an empty store and `.locked` with a stored connection; `unlock()` success → `.ready`, failure stays `.locked`; `canAuthenticate() == false` → `unlock()` goes to `.ready` and the model exposes `showsNoPasscodeWarning == true` (Review Focus 5); `didBecomeInactive()` from `.ready` → `.locked`; `sessionRevoked()` empties the store and sets the notice (Review Focus 6). `PairingModel`: a non-Brievie text sets `failed(canRetry: false)` and a following valid scan still works (Review Focus 1); `.noServerReachable` sets `canRetry: true` and `retry()` re-runs with the kept payload. `WorkspacesModel`: loaded list; `.unauthorized` triggers `sessionRevoked`.
- [ ] **Step 2:** Run; FAIL. Implement models, then views. Run; PASS. `make lint build` clean.
- [ ] **Step 3:** End-to-end check against a running host (`docker compose up` in `../Brievie_host`, setup completed): in the simulator, paste the `qr_payload` from the web page "App koppelen" → the app shows the workspace name. Kill and reopen the app → lock screen → workspaces. Revoke the device on the server (`DELETE /devices/{id}`) → the app returns to pairing with the notice. Record screenshots in the task report. The simulator reaches the host at `https://localhost`.
- [ ] **Step 4:** VoiceOver and largest Dynamic Type pass over all three screens; fix what clips or has no label.
- [ ] **Step 5:** Commit `feat(app): pair, lock and list workspaces`.

---

## Out of scope for 1a (later steps of phase 1)

Scanning documents, on-device OCR, upload queue, document list, tasks, local notifications, share extension, widget, Bonjour discovery, explanation language. English translation of the String Catalog.
