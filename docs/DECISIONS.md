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

## Storage

- **`UserDefaults`: one boolean, `hasLaunchedBefore`** — the single sanctioned use of `UserDefaults` (flag only, never secrets; behind the `LaunchFlag` protocol). Keychain items survive uninstalling the app, `UserDefaults` does not, so a missing flag means "first launch after an install" and the app then clears the stored connection. There is no in-app unpair yet, so without this a reinstall would reopen a pairing the user thought was gone. Consequence: a device restored from a backup (flag restored, Keychain items not) or a new device needs to pair again. Until the check has completed (protected data available, clear succeeded) the app stays on the lock screen and never unlocks a stored connection; it retries on every activation, unlock attempt and when protected data becomes available.

## Release

- **Placeholder app icon and privacy manifest** — `scripts/make-app-icon.swift` draws an opaque 1024x1024 envelope icon until a real design exists. `App/PrivacyInfo.xcprivacy` declares no tracking and no collected data, and only the `UserDefaults` required-reason API (`CA92.1`, the `hasLaunchedBefore` flag); a grep found no other required-reason APIs.

- **Bundle id `nl.stijnvdpol.brievie`** — chosen by the owner on 2026-11-14; fixed after the first upload. The Keychain service default and the test identifiers follow it (nothing was released yet, so no migration).

- **`Brievie.xcodeproj` is committed** — Xcode Cloud builds from the repository and needs the project, the shared scheme and `Package.resolved`. `project.yml` stays the source; `make check-project` (in CI) fails when the committed project differs. The team id lives in `Base.xcconfig` (not a secret). `ci_scripts/ci_post_clone.sh` disables package plugin validation for the OpenAPI generator.

## Open items

- In-app unpair (until then, reinstalling the app is the way to forget a pairing).
- Replace the placeholder app icon with the real design.
- A clear message when the server's API major version becomes newer after pairing (today it surfaces as a generic error).
- A hint when local-network access is denied (today it looks like an unreachable server).
- The device name is always "iPhone" on iOS 16+ without the user-assigned-device-name entitlement.
- Not verified on a real device: the VoiceOver pass, the Face ID success path, the no-passcode warning and the camera scanner (including the first-time permission prompt and the denied state).
