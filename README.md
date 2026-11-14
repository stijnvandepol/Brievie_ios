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

Het Xcode-project wordt gegenereerd en staat niet in git; pas `project.yml` aan.

## Op een echte iPhone draaien

1. Kopieer `Local.xcconfig.example` naar `Local.xcconfig` (staat niet in git) en vul je Apple-team-id in bij `DEVELOPMENT_TEAM`.
2. Draai `make generate`; je team blijft behouden bij elke volgende keer.
3. Kies in Xcode je iPhone als bestemming en start de app.

## TestFlight

Het app-icoon is een tijdelijke placeholder (`scripts/make-app-icon.swift` genereert het); vervang het voor een publieke release.

Handmatige stappen voor de eigenaar (de upload gaat altijd via Xcode, nooit via een script):

1. Registreer de bundle id `nl.brievie.app` in het Apple Developer-portaal.
2. Maak in App Store Connect een app aan: naam Brievie, primaire taal Nederlands, bundle id `nl.brievie.app`.
3. Zet je team-id in `Local.xcconfig` (`DEVELOPMENT_TEAM = <team id>`, zie `Local.xcconfig.example`).
4. Draai `make archive`. Zonder `Local.xcconfig` stopt het target meteen met een melding.
5. Open het archief met `open build/Brievie.xcarchive`, kies in Xcode Organizer **Distribute App** en dan **TestFlight Internal Only**.
6. Verhoog voor elke nieuwe upload `CURRENT_PROJECT_VERSION` in `project.yml`; App Store Connect weigert een build-nummer dat al is gebruikt.
