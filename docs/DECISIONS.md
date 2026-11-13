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
- Every session `LiveBrievieServer` uses refuses redirects (`PinnedSessionDelegate` and the one-off CA delegate): the API never redirects, and a followed redirect could carry the `Authorization` header or the pairing code to another host.
- Server error codes reach the app only from a closed set (`ServerError.passThroughCodes`, plus the codes mapped to their own cases); anything else becomes `http_<status>`. `ServerError.other` and `PairingError.failed` are diagnostic only and never shown to the user.

