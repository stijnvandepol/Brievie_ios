# Decisions

One line per dependency or tooling choice, with the reason.

## Tooling

- **XcodeGen** — the Xcode project is generated from `project.yml`, so `*.xcodeproj` never causes merge conflicts.
- **SwiftLint** (`--strict`, `force_unwrapping` on) — the lint gate locally and in CI.
- **Swift Testing** — the test framework for all targets; ships with the toolchain, no package dependency.

## Package dependencies

- None yet. (swift-openapi-generator, -runtime and -urlsession arrive with the generated API client in Task 5.)
