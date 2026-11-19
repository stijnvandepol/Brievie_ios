# Security

Brievie keeps people's letters: tax, health, debts. A security problem here can hurt
someone, so reports are welcome and taken seriously.

## Reporting a vulnerability

Please do not open a public issue for a security problem.

- Mail **info@brievie.com**, or
- use GitHub's private report form: *Security* → *Report a vulnerability* on this
  repository (if the form is available).

Tell us what you found, how to reproduce it and which version or commit you looked at.
Never send real letters, passwords, tokens or a real `BRIEVIE_MASTER_KEY`; made-up data is
enough.

Brievie is a small project. You get an answer as soon as possible, and you are told when
a fix is released. There is no bug bounty.

## Supported versions

Fixes go into the latest release (until the first release: the `main` branch). Older
versions get no separate fixes: update to the latest one.

## Scope

In scope: the server in `Brievie_host`, the iOS app in `Brievie_ios`, the install script
on brievie.com.

Out of scope: problems that need an attacker who already is administrator of the server
or has the master key, and the AI service or other third parties a user chose to
connect.

## What Brievie promises

`docs/PRIVACY.md` in `Brievie_host` describes what is stored, how it is protected and
what leaves the server. If the software does something else than that document says,
that is a security problem: please report it.

## How this repository is checked

What runs on every pull request and on `main` (`.github/workflows`):

- SwiftLint with `--strict` and the package tests of `BrievieKit` (with a coverage report; no minimum yet).
- A check that the committed Xcode project matches `project.yml`, a simulator build, and the Keychain tests hosted in the app.
- A secret scan of the full history with gitleaks.
- CodeQL (`security-extended`) for the Swift code and for the workflows. On a pull request the Swift analysis (about 40 minutes) runs only when Swift sources, the package manifest or lock, the generated client's contract, the Xcode project or the workflow changed; the check is always reported, and says so when it skipped.
- Dependabot for the GitHub Actions and the Swift packages. Actions are pinned to commit SHAs.

New vulnerabilities and new scanner rules appear without a change of code, so the gitleaks scan of the full history and CodeQL (Swift and workflows) also run on a schedule, on `main`, every Monday, Wednesday and Friday in the early morning (UTC). The macOS build and tests judge the code and run on changes only. A failed scheduled run opens a GitHub issue titled "Scheduled security audit failed" (label `security-audit`), or comments on the one that is still open. The issue names the run and the failed jobs and holds no log lines, because a log can contain a finding that is not yet fixed. CodeQL findings appear under *Security* → *Code scanning*.

What this does not cover: there is no independent security audit or penetration test, the tests do not run against a real Brievie server, and the camera scanner, Face ID and background uploads are checked by hand on a device, not in CI. Passing these checks is not a promise that the app is free of vulnerabilities.
