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
