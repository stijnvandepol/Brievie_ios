# Trash and duplicate letters in the app: design

Date: 2026-11-21. Branch `feat/trash-and-duplicates` (iOS). Contract: `openapi.json` synced from host
`main` 9e73ab7 (host PRs #32 trash and #34 duplicates). Host designs:
`../Brievie_host/docs/superpowers/specs/2026-11-20-trash-design.md` and `2026-11-20-duplicates-design.md`
(their sections "iOS (later; fields the app needs)"). Plan:
`docs/superpowers/plans/2026-11-21-ios-trash-duplicates.md`.

## Intent

The web can put a letter in the trash and can settle a pair of letters that look scanned twice. The phone
is where letters are scanned, so it is also where a wrong or double scan is noticed first. The app gets the
same two things, with the web's words, and nothing the server keeps for the web session.

## Scope

- **Verwijderen.** On a letter (review or confirmed), for a member or admin: "Verwijderen" asks first
  ("Brief verwijderen?", 30 days, can be put back), then the letter goes to the trash, the letter screen
  closes and the post list shows "De brief staat in de prullenbak." with "Ongedaan maken" and "Sluiten".
- **Prullenbak.** A screen with the trashed letters the server lists (sender, kind, letter date, "Verwijderd
  op ... door ...", days left), "Terugzetten" for a member or admin, and one line that removing for good
  is done in the web.
- **Dubbel?** In "Te doen", when the server counts open pairs: a group "Dubbel?" with one row per pair (both
  senders and dates, "Lijkt op elkaar voor 92%"). A letter row with an open pair carries the chip "Dubbel?"
  in every list and in search results.
- **Vergelijken.** A pair opens a compare screen: the first page and the facts of both letters side by
  side, what differs marked, the choice "Welke brief houd je?" (the server's suggestion preselected), "Het
  is dezelfde brief" (merge, with "Taak ook afronden", on by default, where it applies) and "Het zijn twee
  brieven" (dismiss). The merge's other letter goes to the trash, so the same undo shows afterwards.
- **Older servers.** Every new field is optional with a default; an endpoint that answers 404 without a
  Brievie code hides its feature.

## Not in scope

- **Definitief verwijderen and Prullenbak legen.** `purgeDocument` and `emptyTrash` are session-only in the
  contract (`security: SessionAuth` only; the host's ruling 8: a stolen device token cannot destroy post).
  A device token gets 401. The app does not add them to the generator filter and says so in one line on
  the trash screen.
- Opening a trashed letter (the server answers 404 `document_in_trash` on every read); the history lines of
  trash and merge (the app shows no history yet); a duplicate filter on "Alle post" (the server has no such
  list parameter; the pairs come from `listDuplicates`); a link from a letter with the chip to its pair (the
  letter's answer carries the count, not the pair); swipe-to-delete on a list row (one place to delete,
  with its question, is enough for now).

## Who may do what (contract, checked in `openapi.json`)

| Operation | Device token | Role | In the app |
|---|---|---|---|
| `trashDocument` | yes | member, admin (viewer 403) | "Verwijderen" on a letter |
| `restoreDocument` | yes | member, admin | "Ongedaan maken", "Terugzetten" |
| `listTrash` | yes | any | Prullenbak screen (a viewer reads only) |
| `purgeDocument` | **no, session only** | admin | web only |
| `emptyTrash` | **no, session only** | admin | web only |
| `listDuplicates`, `getDuplicate` | yes | any (a viewer gets `[]` / 404) | "Dubbel?" group, compare screen |
| `mergeDuplicate`, `dismissDuplicate` | yes | member, admin (viewer 403) | the two answers on the compare screen |

The app decides nothing about visibility: it shows what the server returns and answers 403/404 as the
server gives them. A viewer gets `duplicate` 0 and no pairs, so the group never shows; the compare screen
still hides the choices when the role cannot edit.

## Where the screens go

- **Post list (`DocumentsView`).** The title menu (now "Te doen", "Alle post", persons) gets a second
  section with one button "Prullenbak" (system image `trash`), shown when the server has a trash. It pushes
  the trash screen. The undo and dismiss notices sit in the list's notices section, like the existing
  "removed" notice: no timer, gone on "Sluiten", on the next scope change, or once acted on.
- **"Te doen".** The group "Dubbel?" comes first, above "Controleren", with its count. Rows push the compare
  screen. "Te doen" is not empty while it has pairs.
- **Letter (`ReviewView`).** "Verwijderen" is a destructive button at the end of the screen (as "Taak
  verwijderen" is a separate button apart from the fields), in states review and done, for a member or
  admin. Not while the server still reads the letter.
- **Compare screen.** Pushed. Two columns of the first page and the facts at regular widths; at compact
  width with an accessibility text size the two letters stand one under the other (`AdaptiveStack`).
  Tapping a page opens the existing letter reader for that letter.
- **Merge question.** A sheet (it holds a switch, which a confirmation dialog cannot), closed when the app
  leaves the foreground like the review's other sheets.

## States and errors

| Situation | What the app does |
|---|---|
| Trash answered | Letter screen closes; list reloads and shows the undo notice |
| "Ongedaan maken" answered | Notice gone, list reloads, the letter opens again |
| "Ongedaan maken" fails (`.notFound`: the purge started, or not visible) | The notice says "De brief kan niet meer worden teruggezet." |
| A letter opened (reminder tap, stale list) answers 404 `document_in_trash` | Letter screen shows "Deze brief staat in de prullenbak." and no retry |
| Any change of a trashed letter answers 404 `document_not_found` | The existing "not found" message |
| 403 `forbidden` | "Je mag dit niet doen in deze werkruimte." (the host's sentence) |
| Upload 409 `document_trashed` | The queued scan stays with "Deze brief staat al in de prullenbak. Zet hem daar terug als je hem weer wilt zien.", no retry; the user removes it (a scan leaves the queue only on the server's confirmation or the user's delete) |
| `listTrash` 404 without code | No "Prullenbak" in the menu; no "Verwijderen" on a letter |
| `duplicate` and `open_duplicate_count` missing | 0: no group, no chip, `listDuplicates` never called |
| `listDuplicates` fails | The group is left out; the rest of "Te doen" shows (like a failing count) |
| Compare: 404 `duplicate_not_found` | "Deze dubbele brieven zijn er niet (meer)." |
| Merge or dismiss: 409 `duplicate_not_open` | "Over deze twee brieven is al gekozen."; back to "Te doen", which reloads |
| Merge: 409 `duplicate_visibility_differs`, or `can_merge` false | The visibility sentence; "Het is dezelfde brief" is gone, "Het zijn twee brieven" stays |
| Merge: 409 `document_processing` | The existing "busy" message; nothing changes |
| Merge answered | Back to "Te doen"; undo notice for the other letter (restore) |
| Dismiss answered | Back to "Te doen"; "Goed. We vragen het niet meer voor deze twee brieven." |
| 409 `document_retained` (reserved, never raised today) | The generic failure |

Days left on a trashed letter: calendar days in the phone's time zone from today to the day of the server's
`purge_after` (never computed from `trashed_at`); 0 or less is "Wordt vandaag gewist" (the host purges
within the hour after `purge_after`).

## Texts (Dutch and English)

English follows the host glossary ("trash", "restore", "duplicate letter", "Duplicate?", "It is the same
letter", "They are two letters", "Also complete the task") and the web's English catalogue where the web
has the same sentence.

| Dutch | English |
|---|---|
| Verwijderen | Delete |
| Brief verwijderen? | Delete letter? |
| De brief gaat naar de prullenbak. Daar blijft hij 30 dagen. Zo lang kun je hem terugzetten. Daarna wordt hij voorgoed gewist. | The letter goes to the trash. It stays there for 30 days. During that time you can restore it. After that it is erased for good. |
| Naar de prullenbak | Move to trash |
| Annuleren (existing) | Cancel |
| De brief staat in de prullenbak. | The letter is in the trash. |
| Ongedaan maken | Undo |
| Sluiten | Close |
| De brief kan niet meer worden teruggezet. | The letter can no longer be restored. |
| Deze brief staat in de prullenbak. | This letter is in the trash. |
| Prullenbak | Trash |
| Brieven in de prullenbak worden na %lld dagen voorgoed gewist. Tot die tijd kun je ze terugzetten. | Letters in the trash are erased for good after %lld days. Until then you can restore them. |
| Definitief verwijderen en de prullenbak legen kan alleen in de webinterface. | Deleting for good and emptying the trash can only be done in the web interface. |
| Verwijderd op %@ door %@ | Deleted on %@ by %@ |
| Verwijderd op %@ | Deleted on %@ |
| Nog %lld dag / Nog %lld dagen (plural) | %lld day left / %lld days left |
| Wordt vandaag gewist | Erased today |
| Terugzetten | Restore |
| Terugzetten: %@ (VoiceOver) | Restore: %@ |
| De brief is teruggezet. | The letter has been restored. |
| De prullenbak is leeg. | The trash is empty. |
| Alleen de nieuwste %lld worden getoond. | Only the newest %lld are shown. |
| Je mag dit niet doen in deze werkruimte. | You are not allowed to do this in this workspace. |
| Deze brief staat al in de prullenbak. Zet hem daar terug als je hem weer wilt zien. | This letter is already in the trash. Restore it there if you want to see it again. |
| Dubbel? | Duplicate? |
| Deze brieven lijken twee keer gescand. Kijk of het dezelfde brief is. | These letters seem to have been scanned twice. Check if it is the same letter. |
| Lijkt op elkaar voor %lld%% | %lld%% alike |
| Mogelijk dubbel | Possible duplicate |
| Deze twee brieven lijken op elkaar. Is het dezelfde brief, twee keer gescand? Kijk wat hetzelfde is en wat verschilt. | These two letters look alike. Is it the same letter, scanned twice? See what is the same and what differs. |
| Brief %lld | Letter %lld |
| Gescand op %@ | Scanned on %@ |
| Eerste pagina van brief %lld | First page of letter %lld |
| Afzender, Soort, Datum, Bedrag, Factuurnummer, Kenmerk, Pagina's, Labels, Op naam van, Taken | Sender, Kind, Date, Amount, Invoice number, Reference, Pages, Labels, Addressed to, Tasks |
| Geen / afgerond | None / completed |
| Verschilt | Differs |
| Verschilt misschien (slecht leesbaar) | May differ (hard to read) |
| Welke brief houd je? | Which letter do you keep? |
| Deze brief houden: brief %lld (VoiceOver) | Keep this letter: letter %lld |
| Het is dezelfde brief | It is the same letter |
| Het zijn twee brieven | They are two letters |
| Deze twee brieven zijn niet voor dezelfde mensen zichtbaar. Daarom kun je ze niet samenvoegen. Kies 'Het zijn twee brieven', of laat ze eerst voor dezelfde mensen zichtbaar zijn. | These two letters are not visible to the same people, so you can't merge them. Choose 'They are two letters', or first make them visible to the same people. |
| Samenvoegen? | Merge? |
| De brief die je houdt, krijgt de labels en personen van allebei. De andere brief gaat naar de prullenbak. Daar kun je hem 30 dagen terugzetten. | The letter you keep gets the labels and persons of both. The other letter goes to the trash. You can restore it from there for 30 days. |
| Taak ook afronden | Also complete the task |
| Op de andere scan is '%@' al afgerond. | On the other scan, '%@' is already completed. |
| Samenvoegen | Merge |
| Goed. We vragen het niet meer voor deze twee brieven. | OK. We won't ask again about these two letters. |
| Deze dubbele brieven zijn er niet (meer). | These duplicate letters are not here (any more). |
| Over deze twee brieven is al gekozen. | A choice has already been made about these two letters. |

Field words for the difference marks are the row titles above. "Let op: ... verschilt." is the web's
summary sentence; the app marks each differing row instead, so it needs no sentence that joins field
names (a list in a sentence translates badly).

## Left to the builder

- The exact layout of the compare rows (a `Grid` or two `VStack`s), the symbol for "Verschilt", the page
  thumbnail size; the facts must stay readable at the largest Dynamic Type size and each row must read as
  one VoiceOver element ("Afzender. Brief 1: Gemeente. Brief 2: Gemeente.").
- Whether "Prullenbak" also gets a count; whether "Terugzetten" is a row button or a swipe action plus a
  context-menu item (it must be reachable without a swipe for VoiceOver).
- How the probe for a trash is shared between the list and the letter screen, as long as a 1c/1d server
  never shows "Verwijderen" or "Prullenbak" and the probe is not repeated on every 3-second refresh.
