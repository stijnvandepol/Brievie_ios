# Brievie iOS

De iOS-app van Brievie. De specificatie staat in `../Brievie_host/docs/SPEC.md`.

## Aan de slag

Nodig: Xcode 26, [XcodeGen](https://github.com/yonaskolb/XcodeGen) en [SwiftLint](https://github.com/realm/SwiftLint)
(`brew install xcodegen swiftlint`).

```sh
make generate   # maakt Brievie.xcodeproj uit project.yml
make test       # tests van Packages/BrievieKit (macOS, geen simulator nodig)
make lint       # swiftlint --strict
make build      # bouwt de app voor een iPhone-simulator (bij voorkeur iPhone 17)
make test-keychain  # Keychain-tests, in de app op de simulator
```

Het Xcode-project wordt gegenereerd uit `project.yml` en staat ook in git, omdat Xcode Cloud het nodig heeft.
Pas `project.yml` aan, draai `make generate` en commit beide; CI controleert dat ze gelijk zijn.

## Op een echte iPhone draaien

Het team-id staat in `Base.xcconfig`. Open `Brievie.xcodeproj`, kies je iPhone als bestemming en start de app.
Wie met een ander team wil signeren, kopieert `Local.xcconfig.example` naar `Local.xcconfig` (staat niet in git).

## TestFlight

Het app-icoon is een tijdelijke placeholder (`scripts/make-app-icon.swift` genereert het); vervang het voor een publieke release.

Eenmalig bij Apple (door de eigenaar):

1. Registreer de bundle id `nl.stijnvdpol.brievie` in het Apple Developer-portaal.
2. Maak in App Store Connect een app aan: naam Brievie, primaire taal Nederlands, bundle id `nl.stijnvdpol.brievie`.

Uploaden kan op twee manieren; er is geen uploadscript.

**Xcode Cloud.** Open `Brievie.xcodeproj`, kies Integrate → Create Workflow en volg de stappen (toegang tot de
GitHub-repo geven, schema `Brievie`, actie Archive met TestFlight Internal Testing). Xcode Cloud zet zelf het
build-nummer. `ci_scripts/ci_post_clone.sh` schakelt de plugin-validatie uit die de OpenAPI-generator anders blokkeert.

**Vanaf je Mac.** Kies in Xcode de bestemming Any iOS Device en dan Product → Archive, of draai `make archive` en
open `build/Brievie.xcarchive`. Kies in de Organizer **Distribute App** en dan **TestFlight Internal Only**.
Verhoog voor elke upload `CURRENT_PROJECT_VERSION` in `project.yml`; App Store Connect weigert een gebruikt build-nummer.
