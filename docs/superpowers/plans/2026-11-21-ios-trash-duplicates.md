# iOS Trash and Duplicate Letters Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** In the app a member deletes a letter to the trash (asked first, undo right after), views and restores trashed letters, sees "Dubbel?" pairs in "Te doen", compares a pair side by side and merges ("Taak ook afronden") or dismisses it; against an older server all of it stays hidden.

**Architecture:** As in 1c: the `DocumentServer` seam and `WorkspaceDocuments` grow with seven calls (trash, restore, list trash; list, get, merge, dismiss pairs); generated types stay inside `LiveBrievieServer`. `FeatureDocuments` gets a `TrashModel` and a `DuplicateModel` (both `@MainActor @Observable`, views dumb), `ReviewModel` gets "Verwijderen", and `DocumentsModel` gets the trash probe, the undo notice and the "Dubbel?" group. `App/RootView.swift` wires the compare screen like `ReviewScreen`.

**Tech Stack:** Swift 6 strict concurrency, SwiftUI, iOS 18+, swift-openapi-generator 1.12.2, Swift Testing, SwiftLint, XcodeGen. No new dependency.

**Spec:** `docs/superpowers/specs/2026-11-21-ios-trash-duplicates-design.md` (texts, states, who may do what). Host field lists: `.superpowers/sdd/2026-11-21-ios-trash-duplicates/host-trash-fields.md` and `host-duplicates-fields.md`, section "Velden voor iOS" (checked against `openapi.json`: `TrashListOut` also has `total`, default 0).

## Global Constraints

- Everything in `CLAUDE.md` holds: English code, Dutch B1 je-vorm plus English for every new key, dumb views, no `!`/`try!`/`as!` outside tests, `async/await` only, VoiceOver and the largest Dynamic Type on every new screen.
- New texts go in `Packages/BrievieKit/Sources/FeatureDocuments/Resources/Localizable.xcstrings` through two new files `DocumentStrings+Trash.swift` and `DocumentStrings+Duplicates.swift`, each with a `[String: String]` table merged into `DocumentStrings.all` (the parity test in `DocumentsModelTests`, `CatalogKeyCoverageTests` and `EnglishCatalogTests` must stay green). `App/Localizable.xcstrings` only if `App/` itself shows a text (not planned). Words exactly as the design's text table; "Nog %lld dagen" is a plural variation.
- A field the server added later is optional with a default: `open_duplicate_count` 0, `duplicate` 0, `trashed_by_name` "", `retention_days` 30, `total` = items shown when 0, `can_merge` true, `blocked_reason` "", arrays `[]`, `uncertain` false.
- `purgeDocument` and `emptyTrash` are session-only (`security: SessionAuth`); they are **not** added to `openapi-generator-config.yaml`. Generator filter gains exactly: `trashDocument`, `restoreDocument`, `listTrash`, `listDuplicates`, `getDuplicate`, `mergeDuplicate`, `dismissDuplicate`.
- Never compute `purge_after` from `trashed_at`: days left come from the server's `purge_after`.
- New `DocumentServer` methods get a default in the protocol extension that throws `ServerError.other("http_404")` (as `search` does), so test fakes keep compiling and a missing endpoint reads as `.notSupported`.
- No document content, sender or label names in logs.
- Branch `feat/trash-and-duplicates`. Conventional commits ending `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Do not push. Never commit an iCloud conflict copy (" 2" in a name).

## Review Focus

1. **A server without these features** (a 1d server, or host `main` between #32 and #34: trash without duplicates): no "Verwijderen", no "Prullenbak", no "Dubbel?" group or chip, and the probe is not repeated on the 3-second refresh. → Task 3 `aServerWithoutATrashHidesItAndIsNotAskedOnEveryTick`; Task 4 `anOlderServerShowsNoDuplicateGroup`.
2. **A letter trashed elsewhere while the phone has it** (open on screen, a reminder tapped, a stale row): the screen says it is in the trash, nothing crashes, a change answers the existing "not found". → Task 3 `aLetterInTheTrashSaysSo`.
3. **Undo that can no longer work** (the purge started, the session was revoked meanwhile): the notice says so or the session ends; nothing restores into another workspace (one `DocumentsModel` per workspace). → Task 3 `aFailedUndoKeepsTheNoticeWithTheReason`, `anUndoAfterRevocationEndsTheSession`.
4. **A pair decided on another device while the compare screen is open**: merge or dismiss answers 409 `duplicate_not_open` (or 404): the screen says so and goes back to a reloaded "Te doen". → Task 4 `alreadyDecidedSaysSoAndFinishes`, `aGonePairSaysSo`.
5. **A second tap while merging or trashing** (slow server): one request, not two. → Task 3 `aSecondTapWhileTrashingSendsNothing`; Task 4 `aSecondTapWhileMergingSendsNothing`.

## File Structure

```
Packages/BrievieKit/Sources/
  BrievieAPI/openapi-generator-config.yaml           # + 7 operations
  BrievieCore/Documents/
    TrashModels.swift                                # TrashedDocument, TrashList (new)
    DuplicateModels.swift                            # DuplicatePair, DuplicateField, DuplicateDifference, TaskTwin (new)
    DocumentModels.swift  OrganiseModels.swift       # openDuplicateCount, InboxCounts.duplicate, seam methods
    WorkspaceDocuments.swift  FakeDocumentServer.swift  DocumentFixtures.swift
  BrievieCore/Server/
    LiveBrievieServer+Trash.swift  LiveBrievieServer+Duplicates.swift   # new
    LiveBrievieServer+Documents.swift  ServerError+Mapping.swift
  BrievieCore/Upload/UploadPolicy.swift              # document_trashed
  FeatureDocuments/
    TrashModel.swift  TrashView.swift  DocumentStrings+Trash.swift       # new
    DuplicateModel.swift  DuplicateView.swift  DocumentStrings+Duplicates.swift   # new
    DocumentsModel+Trash.swift  DocumentsModel+Duplicates.swift          # new
    DocumentsModel.swift  DocumentsModel+Scope.swift  DocumentsView.swift  DocumentsList.swift  DocumentRowView.swift
    ReviewModel.swift  ReviewView.swift
App/RootView.swift                                    # trash flag and compare screen wiring
```

Batches: **A** = Tasks 1, 2, 3 (both seams, trash end to end). **B** = Tasks 4, 5 (duplicates in the app, decisions and device check).

---

### Task 1: The trash through the seam

**Files:**
- Create: `BrievieCore/Documents/TrashModels.swift`, `BrievieCore/Server/LiveBrievieServer+Trash.swift`
- Modify: `BrievieAPI/openapi-generator-config.yaml`, `BrievieCore/Documents/{DocumentModels,WorkspaceDocuments,FakeDocumentServer,DocumentFixtures}.swift`, `BrievieCore/Server/ServerError+Mapping.swift`
- Test: `Tests/BrievieCoreTests/LiveBrievieServerTrashTests.swift` (new), additions to `WorkspaceDocumentsTests.swift`, `GeneratedContractTests.swift`

**Interfaces:**
- Produces (`Equatable, Sendable`):
  - `struct TrashedDocument: Identifiable { summary: DocumentSummary; trashedAt: Date; trashedByName: String; purgeAfter: Date; var id: UUID { summary.id } }`
  - `struct TrashList { items: [TrashedDocument]; retentionDays: Int; total: Int }` (`total` = `max(server total, items.count)`)
- `DocumentServer` gains `trash(_ id: UUID, in: DocumentScope) async throws -> TrashedDocument`, `restore(_ id: UUID, in:) async throws -> DocumentDetail`, `trashList(in:) async throws -> TrashList`; `WorkspaceDocuments` gains `trash(_:)`, `restore(_:)`, `trashList()` (all `throws(DocumentsError)`).
- `DocumentsError` gains `.inTrash` (`document_in_trash`) and `.forbidden` (`forbidden`). Both codes join `ServerError.passThroughCodes`; each generated `.forbidden` response throws `ServerError(status: 403, code:)`.
- `FakeDocumentServer`: `Call.trash(URL, UUID)`, `.restore(URL, UUID)`, `.trashList(URL)`; `onTrash`, `onRestore`, `onTrashList` (default: an empty list, restore answers `DocumentFixtures.detail(id:)`). `DocumentFixtures.trashed(id:sender:by:purgeAfter:)`.
- `TrashedDocumentOut` is its own generated schema: map its summary fields into `DocumentSummary` the same way `init(summary:)` does (share a helper if the generated types allow it; do not copy field logic twice by hand if one generic helper fits).

- [ ] **Step 1: Failing tests**

```swift
@Test func trashPostsAndDecodesTheTrashedLetter()      // POST /api/v1/workspaces/<ws>/documents/<id>/trash, "Bearer tok"; trashedAt, purgeAfter exact; trashedByName "Anna"
@Test func aTrashAnswerWithoutTrashedByNameIsEmpty()   // field absent -> ""
@Test func restorePostsAndReturnsTheLetter()           // POST .../restore -> DocumentDetail.summary.id == id
@Test func trashListDecodesItemsRetentionAndTotal()    // retention_days 30, total 3 with 2 items -> total 3
@Test func aTrashListWithoutTotalCountsItsItems()      // no total, no retention_days -> total 2, retentionDays 30
@Test func aLetterInTheTrashAnswersInTrash()           // getDocument 404 {"code":"document_in_trash",...} -> WorkspaceDocuments.detail throws .inTrash
@Test func forbiddenMapsToForbidden()                  // trash 403 {"code":"forbidden"} -> .forbidden
@Test func aServerWithoutATrashIsNotSupported()        // GET /trash 404 {"detail":"Not Found"} -> .notSupported
@Test func sessionOnlyOperationsAreNotGenerated()      // GeneratedContractTests: the config file's text contains neither "purgeDocument" nor "emptyTrash"
```

- [ ] **Step 2:** `make test` → FAIL (types missing).
- [ ] **Step 3:** Implement the models, the three `LiveBrievieServer` calls, the mapping and the fake.
- [ ] **Step 4:** `make test && make lint` → PASS; `make build` (the generated client compiles warning-free).
- [ ] **Step 5:** Commit `feat(core): trash, restore and the trash list through the server seam`.

### Task 2: Duplicate pairs through the seam

**Files:**
- Create: `BrievieCore/Documents/DuplicateModels.swift`, `BrievieCore/Server/LiveBrievieServer+Duplicates.swift`
- Modify: `openapi-generator-config.yaml`, `BrievieCore/Documents/{DocumentModels,OrganiseModels,WorkspaceDocuments,FakeDocumentServer,DocumentFixtures}.swift`, `LiveBrievieServer+Documents.swift` (summary, search hit and counts mapping), `ServerError+Mapping.swift`
- Test: `Tests/BrievieCoreTests/LiveBrievieServerDuplicatesTests.swift` (new), additions to `LiveBrievieServerDocumentsTests.swift`, `LiveBrievieServerSearchTests.swift`

**Interfaces:**
- Consumes: Task 1's seam pattern and `FakeDocumentServer` shape.
- `DocumentSummary` gains `openDuplicateCount: Int` (init default 0) and `var isPossibleDuplicate: Bool { openDuplicateCount > 0 }`; `InboxCounts` gains `duplicate: Int` (init default 0).
- Produces (`Equatable, Sendable`):
  - `enum DuplicateField: String { case sender, letterDate = "letter_date", documentType = "document_type", amount, invoiceNumber = "invoice_number", paymentReference = "payment_reference", pageCount = "page_count", unknown }` (unknown raw value -> `.unknown`)
  - `struct DuplicateDifference { field: DuplicateField; first: String; second: String; isUncertain: Bool }` (a difference with `.unknown` field is dropped while mapping)
  - `struct TaskTwin { doneDocumentID: UUID; openDocumentID: UUID; type: String; description: String }`
  - `struct DuplicatePair: Identifiable { id: UUID; createdAt: Date; first: DocumentSummary; second: DocumentSummary; suggestedKeepID: UUID; similarity: Int; same: [DuplicateField]; differences: [DuplicateDifference]; taskTwins: [TaskTwin]; canMerge: Bool; blockedReason: String }` (`similarity` clamped to 0...100; `state` is not kept: the server lists open pairs only)
- `DocumentServer` gains `duplicates(in:) -> [DuplicatePair]`, `duplicate(_ id: UUID, in:) -> DuplicatePair`, `mergeDuplicate(_ id: UUID, keep: UUID, completeTwinTasks: Bool, in:) -> DocumentDetail`, `dismissDuplicate(_ id: UUID, in:)`; `WorkspaceDocuments` gains `duplicates()`, `duplicate(_:)`, `mergeDuplicate(_:keep:completeTwinTasks:)`, `dismissDuplicate(_:)`.
- `DocumentsError` gains `.alreadyDecided` (`duplicate_not_open`) and `.visibilityDiffers` (`duplicate_visibility_differs`); `duplicate_not_found` maps to `.notFound`. All three join `passThroughCodes`. `document_retained` is not added (reserved; it reads as `.failed`).
- `FakeDocumentServer`: `Call.duplicates(URL)`, `.duplicate(URL, UUID)`, `.merge(URL, UUID, keep: UUID, completeTwinTasks: Bool)`, `.dismissDuplicate(URL, UUID)` with `on…` closures; `DocumentFixtures.pair(first:second:suggestedKeep:differences:twins:canMerge:)`.

- [ ] **Step 1: Failing tests**

```swift
@Test func aSummaryWithoutTheDuplicateCountHasNone()        // 1d DocumentSummaryOut body -> openDuplicateCount 0, isPossibleDuplicate false
@Test func aSummaryWithAnOpenPairIsAPossibleDuplicate()     // "open_duplicate_count":1 -> true
@Test func countsWithoutDuplicateAreZero()                  // InboxCountsOut without "duplicate" -> 0; with 2 -> 2
@Test func aSearchHitCarriesTheDuplicateCount()
@Test func listDuplicatesDecodesAPair()                     // similarity 92, same [.sender], one difference amount "120.50"/"125.00" uncertain true, one twin
@Test func anUnknownDifferenceFieldIsDropped()              // field "colour" -> not in differences
@Test func aPairWithoutTheNewerFieldsUsesDefaults()         // no same/differences/task_twins/can_merge/blocked_reason -> [], [], [], true, ""
@Test func mergeSendsTheKeptLetterAndTheTwinChoice()        // POST .../duplicates/<id>/merge body == {"keep_document_id":"<uuid>","complete_twin_tasks":false}; answer is the kept DocumentDetail
@Test func dismissPostsAndAcceptsNoContent()                // 204 -> no throw
@Test func notOpenMapsToAlreadyDecided()                    // 409 duplicate_not_open -> .alreadyDecided
@Test func visibilityDiffersMapsToVisibilityDiffers()       // 409 duplicate_visibility_differs
@Test func aGonePairIsNotFound()                            // 404 duplicate_not_found -> .notFound
@Test func aViewerMergeIsForbidden()                        // 403 forbidden -> .forbidden
```

- [ ] **Step 2:** `make test` → FAIL.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** `make test && make lint && make build` → PASS.
- [ ] **Step 5:** Commit `feat(core): duplicate pairs, merge and dismiss through the server seam`.

### Task 3: Delete, undo and the Prullenbak screen

**Files:**
- Create: `FeatureDocuments/{TrashModel,TrashView,DocumentStrings+Trash,DocumentsModel+Trash}.swift`
- Modify: `FeatureDocuments/{ReviewModel,ReviewView,DocumentsModel,DocumentsModel+Scope,DocumentsView,DocumentsList,DocumentStrings}.swift`, `FeatureDocuments/Resources/Localizable.xcstrings`, `BrievieCore/Upload/UploadPolicy.swift`, `App/RootView.swift`
- Test: `Tests/FeatureDocumentsTests/{TrashModelTests,ReviewTrashTests,DocumentsTrashTests}.swift` (new), addition to `Tests/BrievieCoreTests/UploadPolicyTests.swift`

**Interfaces:**
- Consumes: Task 1 (`WorkspaceDocuments.trash/restore/trashList`, `.inTrash`, `.forbidden`).
- `DocumentsModel` (the member/admin right is the existing `canScan`; no new init parameter):
  - `public private(set) var hasTrash: Bool` (false until known): set by one `trashList()` in `load()` (the whole load: first, pull-to-refresh, retry), never in the refresh tick. Success → true, `.notSupported` → false, any other failure keeps the value.
  - `public struct UndoNotice: Equatable, Sendable { let documentID: UUID; let message: String; var failure: String? }`, `public private(set) var undo: UndoNotice?`
  - `func didTrash(_ id: UUID) async` (notice "De brief staat in de prullenbak.", reload), `func undoTrash() async` (restore; success: clear, reload, `openedDocument = id`; failure: `failure` set, `.notFound` → "De brief kan niet meer worden teruggezet.", `.revoked` → `onRevoked`), `func closeUndo()`; `select(_:)` to another scope clears the notice.
  - `public var isShowingTrash: Bool`; `func makeTrashModel() -> TrashModel` (restores call back `load()`).
  - `uploadMessage(for: "document_trashed")` → "Deze brief staat al in de prullenbak. Zet hem daar terug als je hem weer wilt zien." with `canRetry: false`; `UploadPolicy.knownCodes` gains `"document_trashed"`.
- `ReviewModel`:
  - init gains `trashAvailable: Bool = false`; `public var canTrash: Bool` (`canEdit && trashAvailable && (state == .review || state == .done) && !isSaving`).
  - `State` gains `.inTrash` (a load answered `.inTrash`: text "Deze brief staat in de prullenbak.", no retry) and `.trashed` (the view dismisses itself).
  - `public var asksToTrash: Bool`, `func askToTrash()`, `func trash() async` (guarded by `isSaving`), `public var onTrashed: (@MainActor (UUID) -> Void)?`. `.forbidden` shows "Je mag dit niet doen in deze werkruimte."; `.busy` the existing busy message. The question closes in `sceneDidChange(isActive: false)` like the review's sheets.
- `ReviewView`: a destructive "Verwijderen" button at the end (only when `canTrash`), a `confirmationDialog` "Brief verwijderen?" with the 30-day text, "Naar de prullenbak" (destructive) and "Annuleren"; `.inTrash` shows the sentence.
- `TrashModel` (`@MainActor @Observable`): `init(documents: WorkspaceDocuments, canRestore: Bool, clock: TodayClock = .system, onRestored: @escaping @MainActor () -> Void, onRevoked: @escaping @MainActor () -> Void, onMissingPairing: @escaping @MainActor () -> Void)`; `state` (`.loading`, `.loaded`, `.failed(message:)`); `rows: [Row]` with `Row: Identifiable, Equatable { id: UUID; title: String; detail: String?; deletedLine: String; daysLeftLine: String; restoreLabel: String }`; `intro: String` (from `retentionDays`), `webOnlyNote: String`, `capNote: String?` (when `total > items.count`), `notice: String?`; `func load() async`, `func restore(_ id: UUID) async`; `static func daysLeft(until purgeAfter: Date, clock: TodayClock) -> Int` (calendar days from today to the day of `purgeAfter`, both in `clock.timeZone()`). Title: sender, else the existing "Onbekende afzender"; detail: kind and letter date as the post list writes them; dates in `deletedLine` with the list's date style.
- `TrashView`: list with intro, rows ("Terugzetten" as a row button with accessibility label "Terugzetten: <title>", hidden when `!canRestore`), empty "De prullenbak is leeg.", footer `webOnlyNote`, notice on top, pull-to-refresh. Rows do not open a letter.
- `DocumentsView`: title menu gets a second `Section` with `Button("Prullenbak", systemImage: "trash")` when `hasTrash`; `.navigationDestination(isPresented: $model.isShowingTrash)` → `TrashView(model: model.makeTrashModel())` (kept in `@State` so it is made once per push). `DocumentsList.Notices` gains `undo: DocumentsModel.UndoNotice?`, `undoAction`, `closeUndo`: one row with the message, the failure under it, "Ongedaan maken" and "Sluiten".
- `App/RootView.swift`: `ReviewScreen` gets `trashAvailable: model.hasTrash` and `onTrashed: { id in Task { await model.didTrash(id) } }`.

- [ ] **Step 1: Failing tests**

```swift
// TrashModelTests
@Test func daysLeftCountsCalendarDaysInTheLocalTimeZone()   // now 2026-11-21 23:30 Europe/Amsterdam, purgeAfter 2026-12-03T10:00Z -> 12
@Test func aPurgeDayTodayOrPastSaysErasedToday()            // daysLeft 0 and -1 -> "Wordt vandaag gewist"; 1 -> "Nog 1 dag"; 12 -> "Nog 12 dagen"
@Test func rowsSayWhoDeletedTheLetter()                     // "Verwijderd op 9 november 2026 door Anna"; empty name -> "Verwijderd op 8 november 2026"
@Test func aLetterWithoutSenderIsUnknownSender()
@Test func theIntroNamesTheServersRetention()               // retentionDays 30 -> "Brieven in de prullenbak worden na 30 dagen voorgoed gewist. Tot die tijd kun je ze terugzetten."
@Test func aCapNoteWhenTheServerHasMore()                   // total 501, items 500 -> "Alleen de nieuwste 500 worden getoond."; equal -> nil
@Test func restoreRemovesTheRowAndSaysSo()                  // call .restore(id); row gone; notice "De brief is teruggezet."; onRestored called once
@Test func aViewerCannotRestore()                           // canRestore false: restore(id) makes no call
// ReviewTrashTests
@Test func deleteAsksFirstThenTrashesAndReportsTheLetter()  // askToTrash(): no call, asksToTrash true; trash(): one .trash(id), onTrashed(id), state .trashed
@Test func aViewerOrAServerWithoutTrashHasNoDelete()        // canEdit false -> canTrash false; trashAvailable false -> canTrash false
@Test func aLetterInTheTrashSaysSo()                        // detail throws .inTrash -> state .inTrash
@Test func aForbiddenDeleteShowsTheSentence()               // .forbidden -> saveError "Je mag dit niet doen in deze werkruimte."
@Test func aSecondTapWhileTrashingSendsNothing()            // GatedDocumentServer holds the first trash; second trash() -> still one call
@Test func leavingTheForegroundClosesTheQuestion()
// DocumentsTrashTests
@Test func aServerWithoutATrashHidesItAndIsNotAskedOnEveryTick()   // trashList throws http_404 -> hasTrash false; refresh tick -> no second .trashList
@Test func aServerWithATrashShowsIt()
@Test func afterDeletingTheListOffersUndo()                 // didTrash(id) -> undo.message "De brief staat in de prullenbak."
@Test func undoRestoresAndOpensTheLetterAgain()             // undoTrash() -> .restore(id), undo nil, openedDocument == id
@Test func aFailedUndoKeepsTheNoticeWithTheReason()         // restore throws .notFound -> undo.failure "De brief kan niet meer worden teruggezet."
@Test func anUndoAfterRevocationEndsTheSession()            // restore throws .revoked -> onRevoked called
@Test func anotherScopeClearsTheUndo()
// UploadPolicyTests
@Test func anUploadOfATrashedLetterStopsWithItsCode()       // .status(409, "document_trashed") -> .failed(code: "document_trashed"); row canRetry false, the sentence
```

- [ ] **Step 2:** `make test` → FAIL.
- [ ] **Step 3:** Implement; add every new key with `nl` and `en` to the FeatureDocuments catalog (plural variation for "Nog %lld dag(en)").
- [ ] **Step 4:** `make test && make lint && make build` → PASS.
- [ ] **Step 5:** Simulator check against a local host on `main` (9e73ab7 or later), as a member: delete a letter, see the undo notice, undo it (the letter opens), delete again, open "Prullenbak", restore. As a viewer: no "Verwijderen", trash without "Terugzetten". Largest Dynamic Type and VoiceOver on the trash rows and the undo row. Screenshots in the task report; say what was not checked.
- [ ] **Step 6:** Commit `feat(documents): delete to the trash with undo, and the Prullenbak screen`.

### Task 4: "Dubbel?", compare, merge and dismiss

**Files:**
- Create: `FeatureDocuments/{DuplicateModel,DuplicateView,DocumentStrings+Duplicates,DocumentsModel+Duplicates}.swift`
- Modify: `FeatureDocuments/{DocumentsModel,DocumentsModel+Inbox,DocumentsModel+Scope,DocumentsView,DocumentsList,DocumentRowView,DocumentSearchModel,DocumentStrings}.swift`, catalog, `App/RootView.swift`
- Test: `Tests/FeatureDocumentsTests/{DuplicateModelTests,DocumentsDuplicatesTests}.swift` (new)

**Interfaces:**
- Consumes: Task 2 (pairs, `isPossibleDuplicate`, `InboxCounts.duplicate`, `.alreadyDecided`, `.visibilityDiffers`); Task 3 (`DocumentsModel.UndoNotice`, `undoTrash()`).
- `DocumentsModel`:
  - `public struct DuplicateRow: Identifiable, Equatable, Sendable { id: UUID; first: String; second: String; similarity: String; accessibilityLabel: String }` (`first`/`second`: "<sender or Onbekende afzender>, <letter date, else Gescand op …>"; `similarity`: "Lijkt op elkaar voor 92%").
  - `public private(set) var duplicates: [DuplicateRow]`: in scope `.inbox` on a whole load only, asked when `counts.duplicate > 0` (after the counts; never in the tick); a failure leaves `[]` and the rest of "Te doen" shows. Other scopes: `[]`.
  - `Row` gains `isPossibleDuplicate: Bool` (from the summary; search rows too); its accessibility label adds "Dubbel?".
  - `public private(set) var duplicateNotice: String?`; `func didDismissDuplicate() async` (notice "Goed. We vragen het niet meer voor deze twee brieven.", reload); `func didMerge(trashed otherID: UUID) async` (the Task 3 undo notice for `otherID`, reload); `func didFindPairDecided() async` (reload).
  - `emptyText` for "Te doen" applies only when `rows` and `duplicates` are both empty.
- `DuplicateModel` (`@MainActor @Observable`): `init(pairID: UUID, documents: WorkspaceDocuments, canEdit: Bool, persons: [Person], labels: [DocumentLabel], onMerged: @escaping @MainActor (UUID) -> Void, onDismissed: @escaping @MainActor () -> Void, onDecidedElsewhere: @escaping @MainActor () -> Void, onRevoked: @escaping @MainActor () -> Void, onMissingPairing: @escaping @MainActor () -> Void)`
  - `state`: `.loading`, `.loaded`, `.gone(message:)` (404: "Deze dubbele brieven zijn er niet (meer)."), `.failed(message:)`, `.finished` (the view pops).
  - `pair: DuplicatePair?`, `details: [UUID: DocumentDetail]` and `firstPages: [UUID: Data]` (each letter's `detail` and page 1, loaded beside the pair; a failing page leaves a placeholder).
  - `public var keepID: UUID` (starts as `suggestedKeepID`).
  - `rows: [CompareRow]` with `CompareRow: Identifiable, Equatable { id: String; title: String; first: String; second: String; mark: Mark? }`, `enum Mark { case differs, mayDiffer }`. Order: Afzender, Soort, Datum, Bedrag, Factuurnummer, Kenmerk, Pagina's, Labels, Op naam van, Taken ("Brief 1"/"Brief 2" and "Gescand op …" head each page, not a row). Bedrag, Factuurnummer and Kenmerk appear only as differences (the server gives no value when they are the same). A field in `differences` is marked `.differs`, or `.mayDiffer` when `isUncertain`. Labels and names from the passed lists; tasks as "<description>" plus ", afgerond" when done; "Geen" when empty.
  - `canMerge: Bool` (pair's `canMerge` and `canEdit`, false after `.visibilityDiffers`), `blockedNote: String?` (the visibility sentence when the pair cannot merge).
  - `public var asksToMerge: Bool`, `func askToMerge()` (sets `completeTwinTasks = true` each time), `public var completeTwinTasks: Bool`, `twinNotes: [String]` (one "Op de andere scan is '<description>' al afgerond." per twin with `openDocumentID == keepID`; the switch shows only when not empty).
  - `func merge() async`: sends `keep: keepID`, `completeTwinTasks:` the switch when `twinNotes` is not empty, else `true`; guarded by `isSaving`; success → `onMerged(<the other id>)`, `.finished`. `func dismiss() async`: success → `onDismissed()`, `.finished`. `.alreadyDecided` → message "Over deze twee brieven is al gekozen.", `onDecidedElsewhere()`, `.finished`; `.visibilityDiffers` → `canMerge = false`, `blockedNote` set; `.busy` the existing busy message; `.forbidden` the Task 3 sentence; `.notFound` → `.gone`. Without `canEdit` neither call is made. `sceneDidChange(isActive: false)` closes the merge sheet.
- `DuplicateView`: header "Mogelijk dubbel" with the description and the similarity; two first pages side by side ("Eerste pagina van brief 1/2", tap opens `LetterReaderModel` for that letter) in an `AdaptiveStack` (stacked at accessibility sizes); the compare rows, each one VoiceOver element ("Afzender. Brief 1: … Brief 2: … Verschilt"); `Picker("Welke brief houd je?")` with "Brief 1"/"Brief 2" (accessibility "Deze brief houden: brief 1"); buttons "Het is dezelfde brief" (only when `canMerge`) and "Het zijn twee brieven"; the merge sheet: "Samenvoegen?", the text, `Toggle("Taak ook afronden")` with the twin notes when present, "Samenvoegen" and "Annuleren". No choices for a viewer.
- `DocumentsList`/`DocumentsView`: in "Te doen" a first section "Dubbel?" with its count and the explanation "Deze brieven lijken twee keer gescand. Kijk of het dezelfde brief is."; each `DuplicateRow` pushes `compare(id)`. `DocumentRowView` shows a `LabelChip`-style chip "Dubbel?" when `isPossibleDuplicate`. `DocumentsView` gains a second generic view builder `compare: (UUID) -> Compare`; the notice section shows `duplicateNotice`.
- `App/RootView.swift`: `DuplicateScreen(pairID:…)` like `ReviewScreen`, wired to `model.didMerge(trashed:)`, `didDismissDuplicate()`, `didFindPairDecided()`, with `model.persons`, `model.labels` and `canEdit`.

- [ ] **Step 1: Failing tests**

```swift
// DocumentsDuplicatesTests
@Test func theInboxAsksForPairsOnlyWhenTheServerCountsThem()  // duplicate 0 -> no .duplicates call; 2 -> one call, duplicates.count == 2
@Test func anOlderServerShowsNoDuplicateGroup()                // counts without the field -> no call, duplicates empty, no chip
@Test func aFailingPairListLeavesTheRestOfTheInbox()           // duplicates throws .failed -> state .loaded, rows shown, duplicates empty
@Test func theRefreshTickDoesNotAskForPairs()
@Test func pairRowsNameBothLettersAndTheSimilarity()          // "Gemeente Voorbeelddorp, 3 november 2026", "Lijkt op elkaar voor 92%"
@Test func rowsWithAnOpenPairCarryTheChip()                   // isPossibleDuplicate true; accessibilityLabel contains "Dubbel?"
@Test func theInboxIsNotEmptyWhileItHasPairs()
@Test func dismissShowsTheNoticeOnTeDoen()                    // didDismissDuplicate() -> duplicateNotice == "Goed. We vragen het niet meer voor deze twee brieven."
@Test func undoAfterAMergeRestoresTheOtherLetter()            // didMerge(trashed: b) then undoTrash() -> .restore(b)
// DuplicateModelTests
@Test func theSuggestedLetterIsPreselected()
@Test func differingFieldsAreMarkedAndUncertainOnesSaySo()    // sender differs -> .differs; amount uncertain -> .mayDiffer; same -> nil
@Test func amountRowsAppearOnlyWhenTheyDiffer()               // no amount difference -> no "Bedrag" row
@Test func theTwinSwitchFollowsTheKeptLetter()                // twin open on first: keep first -> one note; keep second -> none
@Test func askingToMergeTurnsTheTwinSwitchOnAgain()
@Test func mergeSendsTheChoiceAndReportsTheOtherLetter()      // keep second, switch off -> .merge(id, keep: second, completeTwinTasks: false); onMerged(first.id); state .finished
@Test func withoutATwinTheMergeSendsTheDefault()              // no twin notes -> completeTwinTasks true
@Test func aSecondTapWhileMergingSendsNothing()               // GatedDocumentServer -> one .merge call
@Test func dismissReportsAndFinishes()
@Test func visibilityDiffersHidesTheMergeAndExplains()        // 409 -> canMerge false, blockedNote == the visibility sentence
@Test func aPairTheServerCannotMergeShowsOnlyDismiss()        // canMerge false from the server -> canMerge false, blockedNote set
@Test func alreadyDecidedSaysSoAndFinishes()                  // .alreadyDecided -> message, onDecidedElsewhere called, .finished
@Test func aGonePairSaysSo()                                  // load throws .notFound -> .gone("Deze dubbele brieven zijn er niet (meer).")
@Test func aViewerSeesNoChoices()                             // canEdit false -> canMerge false; merge()/dismiss() make no call
```

- [ ] **Step 2:** `make test` → FAIL.
- [ ] **Step 3:** Implement; catalog keys with `nl` and `en` (the "%" of the similarity is `%%` in the format).
- [ ] **Step 4:** `make test && make lint && make build` → PASS.
- [ ] **Step 5:** Simulator check against the local host with a pair (scan one letter twice from two phones or upload the same photos twice with other `client_id`s): "Dubbel?" in Te doen, the chip in Alle post, the compare screen, merge with "Taak ook afronden", undo; a second pair dismissed; a pair with different visibility shows only "Het zijn twee brieven". Largest Dynamic Type (stacked columns) and VoiceOver over the compare rows. Screenshots in the report.
- [ ] **Step 6:** Commit `feat(documents): duplicate letters in Te doen, compare, merge and dismiss`.

### Task 5: Decisions, current plan, last checks

**Files:**
- Modify: `docs/DECISIONS.md`, `CLAUDE.md` (the "Current plan" line points at this plan)

- [ ] **Step 1:** `make test`, `make lint`, `make build`, `make check-project` → all clean (no `project.yml` change is expected; if `check-project` differs, stop and report).
- [ ] **Step 2:** `docs/DECISIONS.md`, section "Trash and duplicate letters (2026-11-21)": purge and empty are web-only because the contract keeps them session-only (host ruling 8), the app's one line says so; the trash probe (one `listTrash` per whole load) and why there is no other way to tell an older server; undo is a list notice without a timer (unlike the dropped task undo of 2026-11-20: a list notice is not a form banner, and the web's bar works the same); an upload of a trashed letter stays in the queue with a sentence until the user removes it (a scan leaves the queue only on the server's confirmation or the user's delete); the compare screen marks rows instead of the web's "Let op: … verschilt" sentence; what was not verified on a device.
- [ ] **Step 3:** Commit `docs: trash and duplicate letters in the app`.

---

## Out of scope

Deleting for good and emptying the trash (web, session only), the history lines of trash and merge, a swipe to delete on a list row, a link from a letter's chip to its pair, a duplicate filter on "Alle post", the web's "Let op" sentence.
