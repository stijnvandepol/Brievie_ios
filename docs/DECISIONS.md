# Decisions

One line per dependency or tooling choice, with the reason.

## Tooling

- **XcodeGen** — the Xcode project is generated from `project.yml`, so `*.xcodeproj` never causes merge conflicts.
- **SwiftLint** (`--strict`, `force_unwrapping` on) — the lint gate locally and in CI.
- **Swift Testing** — the test framework for all targets; ships with the toolchain, no package dependency.

## Package dependencies

Versions checked on 2026-11-13 against the GitHub tags; exact resolutions are in `Packages/BrievieKit/Package.resolved`.

- **swift-openapi-runtime** `from: 1.13.4` (newest) — runtime for the generated client; `BrievieCore` imports it only to unwrap `ClientError`.
- **swift-openapi-urlsession** `from: 1.4.0` (newest) — `URLSession` transport, so trust is decided by our own session delegate.
- **swift-http-types** `from: 1.8.0` (newest) — already a dependency of the OpenAPI packages; declared explicitly because `APIClient.swift` imports `HTTPTypes` for the bearer-token middleware.
- **swift-openapi-generator** `exact: 1.12.2` (newest is 1.14.4) — build plugin in `BrievieAPI` that generates types and client from `openapi.json` (`generate: [types, client]`, `accessModifier: public`, `namingStrategy: idiomatic`). Pinned below the newest release on purpose: from 1.13.0 the generator emits `public import` lines, and from 1.13.1 it also splits types into files that do not use all of them, which gives "public import ... was not used" warnings on Swift 6.3 (Xcode 26.4); upstream only silences them from Swift 6.4 (`@diagnose`, PR #947). 1.12.2 output compiles warning-free under Swift 6 with complete strict concurrency, so no setting is relaxed for `BrievieAPI`. Move to the newest release once the toolchain is Swift 6.4. Build-time only: nothing of the generator ships in the app.
- **Generator `filter`** — only the operations the app calls (`getHealth`, `getCaCertificate`, `pairDevice`, `listWorkspaces`); a feature that needs another operation adds it to `openapi-generator-config.yaml`. This keeps the generated surface small and avoids generating schemas the app does not use.

## API client

- The contract's paths already include `/api/v1`, so the generated client's server URL is the plain server address from the QR code.
- `APIClient.make(baseURL:session:token:)` takes a `URLSession` rather than a `ServerTrust`: `ServerTrust` lives in `BrievieCore`, which depends on `BrievieAPI`, so `BrievieAPI` cannot name it. `LiveBrievieServer` (in `BrievieCore`) builds the pinned session, passes it in, and invalidates it after each call.
- `openapi.json` is a verbatim copy of the host's file (`make sync-api`), never edited by hand; `API_VERSION` holds its `info.version`.
- Phase 1b adds `listDocuments`, `getDocument`, `getDocumentPage`, `confirmDocument` and `retryDocumentProcessing` to the generator `filter`, plus the schema `UploadMetadataIn`: the JSON in the `metadata` field of the multipart upload, which goes through a background `URLSession` instead of the generated client. Nullable fields arrive as Swift optionals since the host writes them as type arrays (host decision 2026-11-14); a `date` stays a `String` in the generated types.
- `FlexibleDateTranscoder` reads timestamps with and without fractional seconds: the host (Pydantic) sends a fraction unless the time falls on a whole second, and the runtime's default transcoder accepts only the form without.
- Every session `LiveBrievieServer` uses refuses redirects (`PinnedSessionDelegate` and the one-off CA delegate): the API never redirects, and a followed redirect could carry the `Authorization` header or the pairing code to another host.
- Server error codes reach the app only from a closed set (`ServerError.passThroughCodes`, plus the codes mapped to their own cases); anything else becomes `http_<status>`. `ServerError.other` and `PairingError.failed` are diagnostic only and never shown to the user.


## Scanning (phase 1b)

- **VisionKit document scanner + Apple Vision text recognition, on the device** (owner decision 2026-11-14): the app is the only intake in 1b and the server runs no OCR. No new package dependency: VisionKit, Vision, ImageIO and PhotosUI ship with iOS.
- `VisionTextRecognizer` uses `RecognizeTextRequest` (accurate, language correction) with Dutch when the system lists a language with code `nl` (it does on macOS 26 / iOS 26: `nl-Latn-NL`), otherwise automatic detection. Lines are ordered top to bottom, then left to right.
- Pages are uploaded as JPEG, longest edge 2400 px, quality 0.7 (`PageImageEncoder`). Scanner pages and library photos are handed over as compressed data and decoded one at a time, already scaled down (ImageIO thumbnail with transform, which also applies the EXIF orientation), so a 30-page scan never sits in memory as full-size bitmaps.
- `PhotoImportButton` (PhotosPicker) is the way in where the scanner is unavailable (simulator, no camera).
- The test letter (`Tests/BrievieScanTests/Fixtures/letter-nl.png`) is drawn by `make-letter.swift` next to it.

## Upload queue (phase 1b)

- **One directory per queued document, not SwiftData.** `Application Support/Uploads/<id>/` holds `item.json` (the record) and `body.multipart` (the ready-to-send request body). The spec names SwiftData for the queue; a record next to its body is less code, the two disappear together, and a background upload needs the body as a file anyway. Reconsider for the document cache (1c).
- An item is written under `.incoming-<id>` and renamed when complete, so a crash never leaves half an item; leftovers are removed at start. The queue is excluded from backup and readable after the first unlock (the background upload reads it while the phone is locked).
- The item's id is the document's `client_id` on the server: a repeated upload finds the same document.
- Server limits are checked on the phone (`UploadLimits.server`: 30 pages, 32 MiB, 20000 characters of text per page; longer text is cut), so a scan that cannot succeed is never queued.

## Background upload (phase 1b)

- **One background `URLSession` per process** (`nl.stijnvdpol.brievie.upload`), created at launch, also when the system relaunches the app for finished uploads. Its own configuration instead of `SessionConfiguration.hardened`: that one's 30 s resource timeout would end every slow upload; here the system waits for a connection itself (up to 7 days per attempt). No cookies, no cache, no stored credentials, redirects refused.
- **Trust is read per TLS handshake** (`UploadTrustProvider`): the session outlives a pairing, so the pin comes from the stored connection each time. Without a readable pairing the connection is refused; there is no fallback to system trust for a pinned server.
- **The device token travels in the request of a background task**, which iOS keeps outside the app's process until the task ends. Accepted for now; a short-lived upload token is later hardening.
- **Swiping the app away cancels its background uploads** (iOS design). They stay in the queue and go out the next time the app opens. When the system itself ends the app, uploads continue. Such a cancellation counts as "unreachable", never as a failure; only our own refusal of the server's certificate is "untrusted".
- **Retry rules** live in `UploadPolicy` (pure): next URL at once, then back to the first with a backoff of 30 s up to 1 hour, forever; 401 pauses the queue and sends the user to pairing, nothing is deleted; other 4xx answers fail the item with a code from a closed set, and the user can retry or delete it.
- `AppModel` does not know the queue: `AppEnvironment.live` builds transport and coordinator, `RootView` calls `resume()` whenever the app becomes ready.

## Documents (phase 1b)

- **A second seam, `DocumentServer`**, next to `BrievieServer`: the document calls (`documents`, `document`, `pageImage`, `confirm`, `retryProcessing`) take a `DocumentScope` (address, trust, token, workspace). `LiveBrievieServer` implements both. Adding five methods to `BrievieServer` would have forced every pairing fake to grow with them.
- **`WorkspaceDocuments`** is what screens use: it tries the pairing's addresses in order, reads the token from the Keychain, and sorts every failure into a `DocumentsError` (revoked, unreachable, not verified, not found, conflict, ...).
- **`CalendarDate`** (year, month, day) for letter dates and deadlines, never `Date`: a deadline is a day, and a `Date` at midnight in Amsterdam is the day before in Los Angeles.
- A page image is read with a 20 MiB cap; `FakeDocumentServer` and `DocumentFixtures` live in `BrievieCore` because several test targets use them.

## Document list and scanning screens (phase 1b)

- `FeatureDocuments` holds the post of a workspace (`DocumentsModel`, `DocumentsView`) and the scan flow (`ScanFlowModel`). A workspace row opens it through a destination the app supplies (`WorkspacesView(destination:)`), so `FeatureWorkspace` does not depend on it. The tab bar of spec section 13 comes in 1c with the Today screen.
- Screens talk to the queue through the `UploadQueue` protocol (`UploadCoordinator` conforms); a scan on the phone and its document on the server (same id as `client_id`) are one row.
- The list refreshes every 3 seconds only while something is on its way (waiting, uploading, processing) and the screen is visible. There is no push in phase 1.
- All visible text of this target is in `DocumentStrings` (catalog key plus the Dutch default), also for views; the parity test keeps catalog and code equal. A viewer, or a role this app does not know, gets no scan button.

## Storage

- **`UserDefaults`: one boolean, `hasLaunchedBefore`** — the single sanctioned use of `UserDefaults` (flag only, never secrets; behind the `LaunchFlag` protocol). Keychain items survive uninstalling the app, `UserDefaults` does not, so a missing flag means "first launch after an install" and the app then clears the stored connection. There is no in-app unpair yet, so without this a reinstall would reopen a pairing the user thought was gone. Consequence: a device restored from a backup (flag restored, Keychain items not) or a new device needs to pair again. Until the check has completed (protected data available, clear succeeded) the app stays on the lock screen and never unlocks a stored connection; it retries on every activation, unlock attempt and when protected data becomes available.

## Release

- **App icon and privacy manifest** — `scripts/make-app-icon.swift` draws the opaque 1024x1024 app icon: an envelope with a tick as its flap, on a navy square. `App/PrivacyInfo.xcprivacy` declares no tracking and no collected data, and only the `UserDefaults` required-reason API (`CA92.1`, the `hasLaunchedBefore` flag); a grep found no other required-reason APIs.

- **Bundle id `nl.stijnvdpol.brievie`** — chosen by the owner on 2026-11-14; fixed after the first upload. The Keychain service default and the test identifiers follow it (nothing was released yet, so no migration).

- **`Brievie.xcodeproj` is committed** — Xcode Cloud builds from the repository and needs the project, the shared scheme and `Package.resolved`. `project.yml` stays the source; `make check-project` (in CI) fails when the committed project differs. The team id lives in `Base.xcconfig` (not a secret). `ci_scripts/ci_post_clone.sh` disables package plugin validation for the OpenAPI generator.

## Open items

- In-app unpair (until then, reinstalling the app is the way to forget a pairing).
- A clear message when the server's API major version becomes newer after pairing (today it surfaces as a generic error).
- A hint when local-network access is denied (today it looks like an unreachable server).
- The device name is always "iPhone" on iOS 16+ without the user-assigned-device-name entitlement.
- Not verified on a real device: the VoiceOver pass, the Face ID success path, the no-passcode warning and the camera scanner (including the first-time permission prompt and the denied state).
