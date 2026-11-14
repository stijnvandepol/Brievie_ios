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
