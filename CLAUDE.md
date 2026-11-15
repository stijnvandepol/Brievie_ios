# Brievie iOS

Native SwiftUI app that pairs with a self-hosted Brievie server.

- Spec: `../Brievie_host/docs/SPEC.md` (sections 11, 13, 14, 16 step 1a, 18, 19)
- Current plan: `docs/superpowers/plans/2026-11-14-ios-fase-1b.md` (phase 1a: `2026-11-13-ios-fundament.md`)
- Dependency and design decisions: `docs/DECISIONS.md`

## Make targets

| Target | What it does |
|---|---|
| `make generate` | Generate `Brievie.xcodeproj` from `project.yml` (XcodeGen) |
| `make test` | `swift test --package-path Packages/BrievieKit` (runs on macOS, no simulator) |
| `make lint` | `swiftlint --strict` |
| `make build` | Build the app for a simulator (prefers iPhone 17 on the newest iOS runtime; override with `SIMULATOR_ID=<udid>`) |
| `make test-keychain` | Keychain tests, hosted in the app on the simulator (they are skipped by `make test`) |
| `make sync-api HOST=../Brievie_host` | Copy the host's `openapi.json` into `BrievieAPI` and write its `info.version` to `API_VERSION` |

## Rules (short form)

- Code, comments, commits in English. Visible text in Dutch (B1, je-vorm), only via `App/Localizable.xcstrings`; no literal strings in views.
- Swift 6, strict concurrency complete. `async/await` only: no `DispatchQueue`, no manual threads.
- No `!`, `try!` or `as!` outside tests. SwiftLint clean (`force_unwrapping` on).
- Secrets (device token, CA certificate, server config) only in the Keychain, `afterFirstUnlockThisDeviceOnly`. Never `UserDefaults`, never a file.
- Views are dumb: render model state, forward actions. No networking or Keychain in views.
- HTTPS only; no `NSAllowsArbitraryLoads`; non-`https` URLs are rejected at parse time.
- Every screen works with VoiceOver and the largest Dynamic Type size.
- `Brievie.xcodeproj` is generated from `project.yml` and committed (Xcode Cloud needs it). Edit `project.yml`,
  run `make generate` and commit both; CI fails when they differ (`make check-project`).
- No new dependency without a line in `docs/DECISIONS.md`.
- Bundle id `nl.stijnvdpol.brievie`; App Group `group.nl.stijnvdpol.brievie` (reserved, unused in 1a).
- `BrievieAPI` and `BrievieCore` must compile for macOS; guard iOS-only code with `#if canImport(UIKit)` / `#if os(iOS)`.
- File paths from a `URL`: `path(percentEncoded: false)`; the default breaks on the space in `Application Support`.
- A deadline or letter date is a `CalendarDate`, never a `Date`. Scans are on disk in the upload queue before any
  upload starts and leave only after the server confirmed them.
- Tests use Swift Testing. Conventional commits. Never push without being asked.
