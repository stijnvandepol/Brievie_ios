# Brievie iOS

De iOS-app van Brievie. De specificatie staat in `../Brievie_host/docs/SPEC.md`.

## Aan de slag

Nodig: Xcode 26, [XcodeGen](https://github.com/yonaskolb/XcodeGen) en [SwiftLint](https://github.com/realm/SwiftLint)
(`brew install xcodegen swiftlint`).

```sh
make generate   # maakt Brievie.xcodeproj uit project.yml
make test       # tests van Packages/BrievieKit (macOS, geen simulator nodig)
make lint       # swiftlint --strict
make build      # bouwt de app voor de iPhone 17-simulator
```

Het Xcode-project wordt gegenereerd en staat niet in git; pas `project.yml` aan.
