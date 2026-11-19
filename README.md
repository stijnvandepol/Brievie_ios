# Brievie iOS

[![CI](https://github.com/stijnvandepol/Brievie_ios/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/stijnvandepol/Brievie_ios/actions/workflows/ci.yml)
[![CodeQL](https://github.com/stijnvandepol/Brievie_ios/actions/workflows/codeql.yml/badge.svg?branch=main)](https://github.com/stijnvandepol/Brievie_ios/actions/workflows/codeql.yml)

De iOS-app van Brievie: je scant papieren post met je telefoon, de server leest en ordent de brief, en jij
controleert wat eruit komt (afzender, datum, deadline, labels, taken).

**De app werkt alleen samen met een Brievie-server die je zelf draait.** Die staat in
[Brievie_host](https://github.com/stijnvandepol/Brievie_host); meer over het project op
[brievie.com](https://brievie.com). Zonder server kan de app niet koppelen en niets tonen.

Vereist:

- iOS 18 of nieuwer (`project.yml`, `Package.swift`)
- Xcode 26 om te bouwen (CI gebruikt 26.6), Swift 6 met strikte concurrency
- een Brievie-server met API-versie 1.x (de app weigert een andere hoofdversie)

## Wat er nu werkt

- Koppelen met een QR-code of een link van de webpagina van de server.
- Werkruimtes van de server tonen.
- Post toevoegen: scannen met de documentscanner of foto's kiezen. De tekst wordt op de telefoon herkend
  (Apple Vision) en samen met de pagina's naar je server gestuurd. Een scan staat eerst in een wachtrij op de
  telefoon en gaat pas weg na bevestiging van de server; uploaden gaat ook op de achtergrond door.
- De postlijst per werkruimte, en een brief controleren en bevestigen: afzender, datum, deadline en bedrag, met
  de plek in de tekst waar het staat. Voorstellen van de server (labels, "op naam van", taken) kun je kiezen of
  afwijzen; wat door AI is ingevuld, zegt de app erbij.
- Taken afvinken, en deadlines in een eigen agenda per werkruimte zetten (optioneel, uit totdat je het aanzet).
- App-vergrendeling met Face ID of toegangscode, en een scherm dat de brief afdekt in de app-switcher.
- Ontkoppelen, ook als de server zegt dat de telefoon is ingetrokken.

## Koppelen en vertrouwen

Er zijn twee manieren, allebei in `Packages/BrievieKit/Sources/BrievieCore/Pairing`:

- **QR-code.** De code bevat de adressen van de server, een eenmalige koppelcode en, bij een eigen
  certificaatautoriteit (CA), de SHA-256 van het CA-certificaat. De app haalt eerst dat certificaat op en gebruikt
  het alleen als de hash klopt; daarna controleert ze de server (`GET /api/v1/health`) en pas dan gaat de koppelcode naar
  precies dat adres. Een adres dat niet te controleren is, krijgt de code nooit.
- **Link** (`brievie://server#...`). De link bevat alleen adressen, de CA-hash en het id van een koppelcode; geen
  geheim. De app neemt pas contact op als je op "Server zoeken" tikt. De code die je typt verlaat de telefoon niet:
  de app stuurt een bewijs (HMAC-SHA256 over een nonce van de server, met een sleutel uit PBKDF2 over de code),
  gebonden aan het certificaat waarmee de verbinding is gecontroleerd. Een tussenpartij met een ander
  certificaat krijgt een bewijs dat de echte server afwijst.

Na het koppelen vertrouwt de app bij een eigen CA alleen certificaten die door die CA zijn uitgegeven (de
systeemcertificaten tellen dan niet mee); zo kan de server zijn certificaat vernieuwen zonder opnieuw te koppelen.
Een server met een openbaar certificaat gebruikt het gewone systeemvertrouwen. Alleen `https` wordt geaccepteerd,
en redirects worden niet gevolgd, zodat het token of de code niet naar een ander adres kan meereizen (bij
uploads op de achtergrond kan iOS dat niet in alle gevallen afdwingen; zie "Open punten" in `docs/DECISIONS.md`).

## Waar geheimen staan

In de Keychain van de telefoon, met `afterFirstUnlockThisDeviceOnly` (niet gesynchroniseerd, niet in een
back-up naar een andere telefoon): het apparaattoken, het CA-certificaat en de serverinstellingen
(`KeychainSecretStore`). Nooit in een bestand. `UserDefaults` bevat alleen niet-geheime instellingen: of de app
eerder is gestart en per werkruimte de agenda-instellingen.

## Privacy

- De app praat met de server waaraan je haar koppelde, en met niemand anders. Er zit geen analytics- of
  advertentiecode in; de enige pakketten zijn de OpenAPI- en HTTP-pakketten van Apple (zie `docs/DECISIONS.md`). Het
  privacymanifest (`App/PrivacyInfo.xcprivacy`) meldt geen tracking en geen verzamelde gegevens.
- Wat naar je server gaat: de gescande pagina's (JPEG), de herkende tekst en wat je invult of kiest. Of de server
  de tekst daarna aan een AI-dienst geeft, stelt de beheerder van de server in; dat staat niet in deze app maar
  in de documentatie van Brievie_host.
- Op de telefoon blijven de scans in de wachtrij (in de eigen opslag van de app, uitgesloten van back-up) tot de
  server ze heeft bevestigd.
- Camera (koppelcode en post scannen), Face ID, lokaal netwerk (server op je thuisnetwerk vinden) en agenda
  (alleen als je de agenda-schakelaar aanzet) worden pas gevraagd als de functie dat nodig heeft.
- Een agenda-afspraak toont standaard alleen het soort taak ("Betalen (Brievie)"). De omschrijving komt er alleen
  in als je dat per werkruimte aanzet; zo'n afspraak is zichtbaar op het toegangsscherm en voor andere apps met
  agendatoegang. Waar de agenda wordt bewaard (iCloud of op de telefoon), bepaalt je eigen agenda-account.

## Bouwen en draaien

Nodig: Xcode 26, [XcodeGen](https://github.com/yonaskolb/XcodeGen) en
[SwiftLint](https://github.com/realm/SwiftLint) (`brew install xcodegen swiftlint`).

```sh
make generate       # maakt Brievie.xcodeproj uit project.yml
make build          # bouwt de app voor een iPhone-simulator (bij voorkeur iPhone 17)
```

Open `Brievie.xcodeproj`, kies een simulator of je iPhone en start de app. De simulator heeft geen camera: de
QR-scanner en de documentscanner werken daar niet (foto's kiezen en een serverlink wel).

Het team-id staat in `Base.xcconfig`. Wie met een ander team wil signeren, kopieert `Local.xcconfig.example`
naar `Local.xcconfig` (staat niet in git). Het Xcode-project wordt gegenereerd uit `project.yml` en staat ook in
git, omdat Xcode Cloud het nodig heeft: pas `project.yml` aan, draai `make generate` en commit beide.
Meer in [CONTRIBUTING.md](CONTRIBUTING.md).

## Tests en CI

```sh
make test           # tests van Packages/BrievieKit (macOS, geen simulator)
make coverage       # dezelfde tests met dekking per target (build/coverage)
make lint           # swiftlint --strict
make test-keychain  # Keychain-tests, in de app op de simulator
```

GitHub Actions (`.github/workflows`):

- **CI, job `ci`**: lint, tests met dekkingsrapport (als artifact `coverage`), project gelijk aan `project.yml`,
  simulatorbouw en Keychain-tests.
- **CI, job `secrets`**: gitleaks over de hele geschiedenis.
- **CodeQL**: statische analyse van de Swift-code en de workflows, bij elke push naar `main`, elke pull request
  en wekelijks.
- **Dependabot**: wekelijkse updates voor GitHub Actions en de Swift-pakketten.

De tests lopen tegen nepservers en lokale testcertificaten, niet tegen een echte Brievie-server. De camera,
Face ID en uploaden op de achtergrond zijn alleen met de hand op een toestel te controleren (zie "Open punten"
in `docs/DECISIONS.md`).

## Indeling

| Map | Inhoud |
|---|---|
| `App/` | de app zelf: ingang, vergrendeling, privacyscherm, assets en tekstcatalogus |
| `Packages/BrievieKit/` | Swift-package met alle logica en schermen |
| `Packages/BrievieKit/Sources/BrievieAPI` | gegenereerde API-client uit `openapi.json` (kopie van die van de server) |
| `Packages/BrievieKit/Sources/BrievieCore` | koppelen, vertrouwen, Keychain, uploadwachtrij, agenda |
| `Packages/BrievieKit/Sources/BrievieScan` | scannen en tekstherkenning |
| `Packages/BrievieKit/Sources/Feature*`, `BrievieUI` | schermen voor koppelen, werkruimtes en post; gedeelde onderdelen |
| `docs/DECISIONS.md` | keuzes en afhankelijkheden, met reden |
| `scripts/`, `ci_scripts/` | hulpscripts en het script voor Xcode Cloud |

## Status

Vroege versie (`0.1.0`). De app staat niet in de App Store en er zijn geen releases of tags in deze repository. Een build voor
TestFlight is voorbereid (zie hieronder). Niet aanwezig: een Vandaag-scherm met
tabbalk, lokale meldingen, miniaturen in de lijst, de share-extensie en een lokale kopie van documenten om zonder
server te lezen. Wat nog niet op een echt toestel is nagekeken, staat onder "Open punten" in `docs/DECISIONS.md`.

<details>
<summary>TestFlight (voor de eigenaar)</summary>

Eenmalig bij Apple: registreer de bundle id `nl.stijnvdpol.brievie` en maak in App Store Connect een app aan.
Uploaden kan via Xcode Cloud (`ci_scripts/ci_post_clone.sh` schakelt de plugin-validatie uit die de
OpenAPI-generator anders blokkeert) of vanaf een Mac: `make archive`, open `build/Brievie.xcarchive` en kies in
de Organizer **Distribute App** en dan **TestFlight Internal Only**. Verhoog voor elke upload
`CURRENT_PROJECT_VERSION` in `project.yml`. Het app-icoon wordt gemaakt door `scripts/make-app-icon.swift`.

</details>

## Beveiliging

Een beveiligingsprobleem melden: zie [SECURITY.md](SECURITY.md). Open daarvoor geen publieke issue.

## Licentie

Licentie nog niet gekozen: er is geen `LICENSE`-bestand, dus er is geen toestemming om de code te hergebruiken.
