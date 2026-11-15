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
- **Generator `filter`** — only the operations the app calls (`getHealth`, `getCaCertificate`, `pairDevice`, `revokeDevice`, `listWorkspaces`); a feature that needs another operation adds it to `openapi-generator-config.yaml`. This keeps the generated surface small and avoids generating schemas the app does not use.

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
- An item is written under `.incoming-<id>` and renamed when complete, so a crash never leaves half an item; leftovers are removed at start. A directory whose `item.json` is missing or not an item can never be uploaded: it is removed at start and the post list says once "1 scan kon niet worden gelezen en is verwijderd". A record that exists but cannot be opened yet (before the first unlock) is kept. The queue is excluded from backup and readable after the first unlock (the background upload reads it while the phone is locked).
- The item's id is the document's `client_id` on the server: a repeated upload finds the same document.
- Server limits are checked on the phone (`UploadLimits.server`: 30 pages, 32 MiB, 20000 Unicode code points of text per page, as the host counts them; longer text is cut between whole characters), so a scan that cannot succeed is never queued.

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

## Review screen (phase 1b)

- `ReviewModel` turns the server's proposals into a draft: a value the letter does not support (confidence 0) is shown as a hint, never pre-filled; a deadline the user changes becomes `manual` and loses its quote, so the source shown always belongs to the value; an invoice due date without a payment action adds a "Betaal de rekening" task. Nothing is sent before "Bevestigen".
- "Waar staat dit?" shows the letter text with the quote marked (`QuoteLocator`: ignores case, accents and line breaks; it only finds what to highlight). Marking the place on the page image needs text positions from Vision: later.
- AI-written text carries "Gemaakt door AI. Controleer of het klopt."; a deadline or amount below the server's threshold shows an orange "Controleer dit goed" label with an icon.
- **Every value the user confirms is judged the same way** (sender, letter date, document type, task type, task description, deadline): "Controleer dit goed" when the server sets `needs_attention`, the confidence is below 0.85 (the server's `NEEDS_ATTENTION_BELOW` for deadlines and amounts, here applied to all) or there is no quote; confidence 0 is never pre-filled but shown as "Voorstel van AI, niet teruggevonden in de brief"; every pre-filled value with a quote has its own "Waar staat dit?". The pay task the app adds for an invoice due date says "Niet gecontroleerd" on its type and text (not read from the letter); only its date has a source. Amounts (`invoice_amount_incl`) and `invoice_number` are not shown or confirmed: the confirm contract has no field for them.
- **A changed value is the user's own.** The draft keeps each pre-filled value's origin (value, quote, mark); quote and mark show only while the field still holds that exact value, so changing it hides both and typing the original back restores them. The deadline's `deadline_source`/`deadline_quote` sent on confirm follow the same rule.
- "Post toevoegen" is a menu with the scanner and "Kies foto's" (photos of the pages): the scanner reports itself as supported in the simulator but has no camera there, and a photo of a letter is a real way in too.
- File paths are built with `path(percentEncoded: false)`: the default percent-encodes the space in `Application Support`, and the queue then finds nothing (caught in the simulator; a test now uses a directory with a space).

## Fixes after the whole-branch reviews (phase 1b)

- **A scan belongs to one server.** A queued item stores `ServerConnection.serverID` (the pinned CA's fingerprint, or the set of hosts without a private CA). After pairing with another server it is not sent: it fails with `server_changed` and can only be deleted. Pairing the same server again (new device id) sends it.
- **Every attempt has an id** (in the task description and on the item). An event of an earlier attempt, such as the late cancellation of a task the system ended, is ignored, so an item is never uploaded twice in parallel.
- **No pairing is not an untrusted server.** An upload that starts after the pairing was cleared (a 401 elsewhere) is paused and goes out after the next pairing, instead of failing as "not verified".
- **The system's completion handler** is also called when its events were handled before the app delegate handed it over. Every handler the system hands over is kept and called exactly once, on the main actor; an early delivery is used by the next handler only.
- **A scan with a page that could not be loaded is refused as a whole** (a photo only in iCloud, a scanner page without data), with "Een pagina kon niet worden gelezen": never uploaded with a page missing.
- **A scan on its way can be deleted**, and shows "Wacht op verbinding" until the first bytes are sent.
- **A review pre-filled by AI says so at the top** ("Ingevuld door AI. Controleer of het klopt voordat je bevestigt."), next to the label on the summary.
- **The paired app stays in the view tree while locked**, under an opaque lock screen, so a half-filled review survives a trip to another app. Sheets above it close when the scene leaves the foreground (the letter-text sheet when inactive, the scanner and photo picker in the background), and polling stops while the app is not active.

## Unpair

- **"Ontkoppelen" on the Workspaces screen: best-effort server revoke, queue wiped, notice when the server could not be told.** `revokeDevice` (`DELETE /api/v1/devices/{id}` with the device token) gets 5 seconds over all the pairing's addresses; offline, no answer, a pin failure or any refusal never blocks unpairing. 401 and 404 `device_not_found` count as told (the server no longer knows the device). Then every upload is cancelled and the whole queue directory emptied (unreadable items and interrupted writes too), the stored connection and token are cleared (the `hasLaunchedBefore` flag stays), and pairing shows; only when the server was not told it says once "Deze telefoon staat nog als apparaat op de server. Trek hem daar in onder Apparaten." The confirmation names the number of waiting scans (catalog plural).
- **Revoked and unpaired end in one path** (`AppModel.finishForgetting`): empty the queue (unpair only), clear the store, show pairing. When a step fails the app stays locked and every activation and unlock attempt retries it; it never shows pairing with a token left in the Keychain. A 401 whose clear fails now stays locked too (before, it showed pairing anyway). The retry lives in memory: a killed app reopens on the stored pairing (unlock, then a 401 if the server was told).

## Storage

- **`UserDefaults`: one boolean, `hasLaunchedBefore`** — the single sanctioned use of `UserDefaults` (flag only, never secrets; behind the `LaunchFlag` protocol). Keychain items survive uninstalling the app, `UserDefaults` does not, so a missing flag means "first launch after an install" and the app then clears the stored connection. Without this a reinstall would reopen a pairing the user thought was gone (deleting the app is not unpairing it). Consequence: a device restored from a backup (flag restored, Keychain items not) or a new device needs to pair again. Until the check has completed (protected data available, clear succeeded) the app stays on the lock screen and never unlocks a stored connection; it retries on every activation, unlock attempt and when protected data becomes available.

## Release

- **App icon and privacy manifest** — `scripts/make-app-icon.swift` draws the opaque 1024x1024 app icon: an envelope with a tick as its flap, on a navy square. `App/PrivacyInfo.xcprivacy` declares no tracking and no collected data, and only the `UserDefaults` required-reason API (`CA92.1`, the `hasLaunchedBefore` flag); a grep found no other required-reason APIs.

- **Bundle id `nl.stijnvdpol.brievie`** — chosen by the owner on 2026-11-14; fixed after the first upload. The Keychain service default and the test identifiers follow it (nothing was released yet, so no migration).

- **`Brievie.xcodeproj` is committed** — Xcode Cloud builds from the repository and needs the project, the shared scheme and `Package.resolved`. `project.yml` stays the source; `make check-project` (in CI) fails when the committed project differs. The team id lives in `Base.xcconfig` (not a secret). `ci_scripts/ci_post_clone.sh` disables package plugin validation for the OpenAPI generator.

## Open items

- A clear message when the server's API major version becomes newer after pairing (today it surfaces as a generic error).
- A hint when local-network access is denied (today it looks like an unreachable server).
- The device name is always "iPhone" on iOS 16+ without the user-assigned-device-name entitlement.
- **Redirects in the background upload are not verified.** The delegate refuses redirects, but Apple documents that background sessions follow them without asking. With a pinned private CA the redirect target must still present a certificate of that CA, so the scan cannot leave the server; with a public certificate (no pin) a 307/308 could carry the scan to another host. To check on a device, and to solve (for example by refusing an upload whose final URL differs) before public-certificate servers are supported for real.
- From the reviews, not fixed: `.secureConnectionFailed` (often temporary, also a captive portal) fails an item as "untrusted" until the user retries; page encoding runs on the main actor (a 30-page scan freezes the screen for seconds); the list keeps asking the server every 3 s while a scan waits offline; a retry created in the background may wait for Wi-Fi and power.
- Fixed after the 1b reviews: page text cut by code points; unreadable queue items removed and reported; a 409 on confirm while still in review explains itself and keeps the edits; "Opnieuw verwerken" asks before replacing a changed draft; edited values drop their quote and mark; the confirmed task line is a catalog format and the tasks header shows once; retry and delete are also a context menu, accessibility actions and visible buttons on a failed row; refused camera access shows a notice with "Open Instellingen" and "Kies foto's".
- Phase 1b, not verified on a real device (the simulator has no camera and no real background relaunch): the document scanner itself, an upload that continues after the system ended the app, the queue going out by itself when the network returns, upload while the phone is locked, and a VoiceOver pass over the document list, scan flow and review screen. Checked in the simulator: the whole line with a photo of a letter (text recognition on the device, upload, processing, review with "Waar staat dit?", confirm), and the largest Dynamic Type size on the list and the review.
- Thumbnails in the document list; a document cache for reading without the server (1c); marking the source on the page image instead of in the text; the share extension (1d); deleting a document on the server.
- The simulator's "Post toevoegen" menu offers the scanner although it has no camera there.
- Not verified on a real device: the VoiceOver pass, the Face ID success path, the no-passcode warning and the camera scanner (including the first-time permission prompt and the denied state).
