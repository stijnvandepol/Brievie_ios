# Contributing

Thanks for looking. Brievie iOS is the app of a small, self-hosted project, so a short conversation before a big change saves everybody time: open an issue first for anything larger than a fix.

Security problems do not go in an issue: see [SECURITY.md](SECURITY.md).

## Requirements

- macOS with **Xcode 26** (CI uses 26.6). The app targets iOS 18 and builds with Swift 6 and strict concurrency.
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) and [SwiftLint](https://github.com/realm/SwiftLint): `brew install xcodegen swiftlint`.
- For the app to do anything you need a Brievie server ([Brievie_host](https://github.com/stijnvandepol/Brievie_host)). The unit tests need none.

## Make targets

Run them from the repository root.

| Target | What it does |
|---|---|
| `make lint` | `swiftlint --strict` |
| `make test` | package tests of `Packages/BrievieKit` on macOS (no simulator) |
| `make coverage` | the same tests with code coverage; writes `build/coverage/` |
| `make check-project` | regenerates `Brievie.xcodeproj` and fails if it differs from what is committed |
| `make build` | builds the app for an iPhone simulator |
| `make test-keychain` | Keychain tests, hosted in the app on the simulator (`make test` skips them) |
| `make generate` | generates `Brievie.xcodeproj` from `project.yml` |
| `make sync-api HOST=../Brievie_host` | copies the host's `openapi.json` into `BrievieAPI` |

CI runs `lint`, `coverage`, `check-project`, `build` and `test-keychain`, plus a secret scan and CodeQL. Run the first three before you push.

## Running the app

**Simulator.** Open `Brievie.xcodeproj`, pick an iPhone simulator and run. The simulator has no camera: the QR scanner and the document scanner do not work there, but a server link and "Kies foto's" do. Pairing only finishes against a running Brievie server.

**Real iPhone.** The team id is in `Base.xcconfig`. To sign with your own team, copy `Local.xcconfig.example` to `Local.xcconfig` (not in git) and set your team there. Select your iPhone as destination and run. Changing bundle identifiers or signing settings in a pull request needs a reason in the description.

## Rules

The short form is in [CLAUDE.md](CLAUDE.md); the reasons are in [docs/DECISIONS.md](docs/DECISIONS.md). The ones reviewers check most:

- Code, comments and commits in English; visible text in Dutch (B1, je-vorm), only through `App/Localizable.xcstrings` or the target's strings type. No literal strings in views.
- No `!`, `try!` or `as!` outside tests. `async/await` only. Secrets only in the Keychain.
- HTTPS only; the pinned-CA trust logic is not loosened for convenience.
- `Brievie.xcodeproj` is generated: edit `project.yml`, run `make generate`, commit both.
- A new dependency needs a line in `docs/DECISIONS.md` first.
- Tests use Swift Testing, and logic gets its test with the change.

## Commits and pull requests

- [Conventional Commits](https://www.conventionalcommits.org/): `feat:`, `fix:`, `docs:`, `test:`, `ci:`, `chore:`, optionally with a scope, for example `fix(pairing): ...`. One logical change per commit.
- Open the pull request against `main`. Fill in the template, in particular what you did **not** check: it is fine to say "not tried on a real device".
- CI must be green. `.github/CODEOWNERS` asks the maintainer for review; changes to pairing, trust, the Keychain or uploads get a closer look.
- Do not commit secrets, real letters or real server addresses. Test values must be made up.

## Licence and contributions

The code is licensed under AGPL-3.0-or-later (`LICENSE`). The author also publishes the app in
the App Store, whose terms are not compatible with the AGPL for anyone who does not hold the
copyright. For that reason a code contribution is merged only after its author has signed a
contributor agreement that lets the project distribute the contribution through the App Store
and under other licences. That agreement does not exist yet. Until it does, pull requests with
code from outside are not merged; bug reports, ideas and security reports are welcome.
