# Mijn taken (iOS) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give every paired member a "Mijn taken" list in the app, next to the Inbox: their open tasks from
their own post, by date, with amount, sender, for whom and why, to tick off, pick up, hand over or date; and
let reminders and the phone calendar follow that list instead of every task of the workspace.

**Architecture:** The server computes everything (reason, group, `days_left`, `today`, counts, who may see
what); the app only renders and words it. Transport goes through the existing seam
(`DocumentServer` → `LiveBrievieServer` → `WorkspaceDocuments`), the screen is a new `MyTasksModel` /
`MyTasksView` pair inside `FeatureDocuments`, shown in place of the post list when "Mijn taken" is picked in
the title menu (the same pattern as the trash: `TrashModel`, `DocumentsModel+Trash.swift`). No new target, no
new dependency.

**Tech Stack:** Swift 6 (strict concurrency), SwiftUI, Observation, swift-openapi-generator 1.12.2, Swift
Testing, String Catalogs (`nl` source, `en`).

**Spec:** `../Brievie_host/docs/superpowers/specs/2026-11-21-mijn-taken-design.md` (sections 5, 6, 8, 9, 10,
11, 13, 14). Server plan: `../Brievie_host/docs/superpowers/plans/2026-11-21-host-mijn-taken.md` (section
"iOS"). Web reference: `../Brievie_host/web/src/routes/tasks.tsx`, `web/src/components/task-row.tsx`,
`web/src/components/task-actions.tsx`, `web/src/task-time.ts`; English texts:
`../Brievie_host/web/src/locales/en/messages.po`.

**Start point:** `main` after iOS PR #23 (`feat/trash-and-duplicates`) **and** PR #24 (`feat/inbox-name`)
are merged. Both touch `DocumentsModel*.swift`, `DocumentsView.swift`, `DocumentsList.swift`,
`FeatureDocuments/Resources/Localizable.xcstrings`, `openapi.json` and the generator config; do not start
before both are on `main`. Check: `git log origin/main --oneline | grep -E "#23|#24"` shows both merges, and
`Sources/FeatureDocuments/TrashModel.swift` exists and `DocumentStrings.scopeInbox` reads "Inbox".

---

## Global Constraints

From `CLAUDE.md` (iOS):

- Code, comments, commits in English. Visible text in Dutch (B1, je-vorm), only via the target's
  `Localizable.xcstrings`; no literal strings in views. Every key also has an `en` value with the same
  placeholders (`EnglishCatalogTests`), plural keys carry `one` and `other` in both languages.
- Swift 6, strict concurrency complete. `async/await` only: no `DispatchQueue`, no manual threads.
- No `!`, `try!` or `as!` outside tests. SwiftLint clean (`force_unwrapping` on).
- Views are dumb: render model state, forward actions. No networking or Keychain in views.
- Every screen works with VoiceOver and the largest Dynamic Type size.
- No new dependency without a line in `docs/DECISIONS.md` (this plan adds none).
- `BrievieAPI` and `BrievieCore` must compile for macOS; guard iOS-only code with `#if os(iOS)`.
- A deadline or letter date is a `CalendarDate`, never a `Date`.
- A field the server added later is optional: read it with a default, so the app still works against an older
  server.
- The app writes only in calendars it made itself, and never without the switch being on.
- Tests use Swift Testing. Conventional commits. Never push without being asked.
- `Brievie.xcodeproj` is generated from `project.yml`; this plan adds no file to the App target, so no
  `make generate` is needed (if one is added after all: edit `project.yml`, `make generate`, commit both).

From the spec:

- **The server is the only gate** (S 8). The app shows what `listMyTasks` / `countMyTasks` return, never
  derives a task, a count or a name list itself, and never shows a task it did not get from the server for
  this member. No count of hidden tasks anywhere.
- **Days and groups come from the server** (S 11): `today` and `days_left` are computed in Europe/Amsterdam.
  The app never recounts them from the phone's clock; it only puts them into words.
- Groups, in this order: "Te laat", "Binnen 7 dagen", "Later", "Zonder datum" ("Datum nodig" rows first in
  that group, as the server sorts them). "Binnen 7 dagen", never "Deze week" (MT9).
- Overdue is shown in the warning colour **and** in words (never colour alone) (S 6.3).
- A row, in this order (S 6): tick box labelled "Klaar: <omschrijving>"; the action; when; amount; "Van
  <afzender> · <voor wie>"; why ("Uit de brief: '…'" / "Datum zelf ingevuld"); "Datum nodig" with the term
  quote and "Datum invullen"; "Brief bekijken" (secondary).
- Ticking keeps the row in place, struck through, with "Ongedaan maken" until the screen is left or
  refreshed; then it is under "Afgerond" (30 days, "Afgevinkt door Anne op 20 nov", "Toch niet klaar").
- "Op te pakken" only when `split` is true (Organisatie), with "Ik doe dit" per row; at home it is not shown.
- Assignment only through `assignTask`; "Geef aan…" lists exactly what `listTaskAssignees` returns, names
  only. A 422 `assignee_cannot_read` gets the app's own sentence, never the server's message.
- Reminders read `part=mine`; "Op te pakken" gets no reminders; an older server (404) keeps the old
  behaviour (`listTasks`). The calendar gets the setting "Welke taken: Mijn taken (standaard) / Alle taken".
  "Datum nodig" tasks get no reminder (no date).
- Lock-screen and calendar privacy stay as they are: no letter text in a reminder unless "toon afzender";
  the event title is the task type. No log line holds a description, sender, amount or quote.
- `amount` is a decimal string ("1234.56"), empty when unknown (MT8); the app parses it locale-free and
  shows it with the user's locale as euros.
- App-specific naming (owner decision): the review list is called **Inbox** and stays the start screen; the
  waiting-letters line therefore links "Naar Inbox", not "Naar Te doen". "Mijn taken" sits directly above
  "Inbox" in the title menu (spec S 4 order); the start screen does not change (spec Q1).
- **Status later:** a later design adds a letter status badge (Nieuw / Openstaand / Afgehandeld, "wacht op
  reactie", "uitgesteld"). The task row gets an empty trailing badge slot for it; nothing else is built.

## Review Focus

1. **A truncated list** (`truncated == true`, 500 open tasks): the screen says "Alleen de eerste 500 taken
   worden getoond." and the counts in the menu still come from `countMyTasks`, not from `items.count`.
   Test in Task 4 (`truncatedListSaysSoAndKeepsServerCounts`).
2. **An amount in the user's own notation**: "1.234,56" typed on a Dutch phone and "1,234.56" on an English
   one both go out as `"1234.56"`; a server `"1234.5"` shows as "€ 1.234,50" / "€1,234.50"; garbage stays
   empty, never `0`. Tests in Task 1 (`TaskAmountTests`) and Task 9.
3. **An older server** (no `/my-tasks`, 404 without a Brievie code): reminders and calendar fall back to
   `listTasks`, the "Mijn taken" entry is not offered, nothing shows an error. Tests in Task 2
   (`myTasksOnAnOlderServerIsNotSupported`), Task 7 (`menuHidesMyTasksOnAnOlderServer`) and Task 8
   (`phoneTasksFallBackToListTasksOn404`).
4. **A task that vanished meanwhile** (ticked or released elsewhere, letter trashed, sight lost): an action
   answering 404 `task_not_found` removes the row quietly and reloads; it never resurrects the row or shows
   a raw error. Test in Task 4 (`tickOnAVanishedTaskRemovesTheRow`) and Task 5
   (`takeOnAVanishedTaskReloads`).
5. **A viewer, and a member without a person**: a viewer sees "Je kunt taken bekijken, maar niet afvinken."
   and no tick box, swipe or action is enabled (also when `can_edit` is absent, from the role); a member
   with `has_person == false` sees the "Je account hangt nog niet aan een naam…" sentence above an empty or
   short list. Tests in Task 4 (`viewerGetsNoActions`, `memberWithoutPersonIsTold`).

---

## File map

`Packages/BrievieKit/` is abbreviated `K/`.

| File | Task | Responsibility |
|---|---|---|
| `K/Sources/BrievieAPI/openapi.json`, `API_VERSION`, `openapi-generator-config.yaml` | 1 | synced API, six more operations |
| `K/Sources/BrievieCore/Documents/OrganiseModels.swift` | 1 | `WorkspaceTask` new fields |
| `K/Sources/BrievieCore/Documents/MyTaskModels.swift` (new) | 1 | `TaskGroup`, `TaskReason`, `MyTasksPart`, `MyTasksStatus`, `MyTasks`, `MyTaskCounts`, `TaskAssignee` |
| `K/Sources/BrievieCore/Documents/TaskAmount.swift` (new) | 1 | parse and write the API's decimal string |
| `K/Sources/BrievieCore/Server/LiveBrievieServer+Tasks.swift` | 1 | decode the new `TaskItemOut` fields |
| `K/Sources/BrievieCore/Server/LiveBrievieServer+MyTasks.swift` (new) | 2 | `listMyTasks`, `countMyTasks`, `assignTask`, `listTaskAssignees`, `setTaskDeadline`, `getMe` |
| `K/Sources/BrievieCore/Documents/DocumentModels.swift` | 2, 9, 10 | `DocumentServer` protocol; `ConfirmedTask`, `TaskDraft` fields |
| `K/Sources/BrievieCore/Documents/WorkspaceDocuments.swift` | 2, 8 | wrappers, error verdicts, `phoneTasks` |
| `K/Sources/BrievieCore/Server/ServerError+Mapping.swift` | 2 | pass-through codes |
| `K/Sources/BrievieCore/Documents/FakeDocumentServer.swift` | 2 | fake answers and calls |
| `K/Tests/FeatureDocumentsTests/GatedDocumentServer.swift` | 2 | forwarders |
| `K/Sources/FeatureDocuments/TaskWords.swift` (new) | 3 | the row's words |
| `K/Sources/FeatureDocuments/DocumentStrings+MyTasks.swift` (new) | 3–7 | Dutch keys of this feature |
| `K/Sources/FeatureDocuments/MyTasksModel.swift` (new) | 4 | load, groups, tick, undo, Afgerond |
| `K/Sources/FeatureDocuments/MyTasksModel+Actions.swift` (new) | 5 | Ik doe dit, release, hand over, set a date |
| `K/Sources/FeatureDocuments/MyTasksView.swift`, `MyTaskRowView.swift`, `MyTaskSheets.swift` (new) | 6 | the screen |
| `K/Sources/FeatureDocuments/DocumentsModel+MyTasks.swift` (new), `DocumentsModel.swift`, `DocumentsView.swift`, `DocumentsList.swift` | 7 | menu entry, count, Inbox link, switching |
| `App/RootView.swift` | 7, 8 | wiring |
| `App/AppEnvironment.swift`, `App/BrievieApp.swift` | 8 | task sources for reminders and calendar |
| `K/Sources/BrievieCore/Calendar/CalendarSettings.swift`, `K/Sources/FeatureWorkspace/CalendarSettingModel.swift`, `SettingsView.swift`, `WorkspaceStrings.swift` | 8 | "Welke taken" |
| `K/Sources/FeatureDocuments/ReviewDraft.swift`, `ReviewView.swift`, `K/Sources/BrievieCore/Server/LiveBrievieServer+Documents.swift` | 9 | amount in the review |
| `K/Sources/FeatureDocuments/ConfirmedDocumentSections.swift`, `ConfirmedDocumentModel.swift` | 10 | amount, "Bij …", Ik doe dit on the letter |
| `K/Sources/FeaturePairing/PairingStrings.swift`, `PairingView.swift` | 11 | the own-phone sentence |
| `docs/GLOSSARY-en.md` | 3 | the new terms |
| `K/Sources/FeatureDocuments/Resources/Localizable.xcstrings`, `FeatureWorkspace/…`, `FeaturePairing/…` | 3–11 | `nl` + `en` |

Test commands (from the repo root): one suite
`swift test --package-path Packages/BrievieKit --filter <Suite>`; everything `make test`; lint `make lint`;
simulator build `make build`.

---

### Task 1: Sync the API and decode the new task fields

**Files:**
- Modify: `K/Sources/BrievieAPI/openapi.json`, `K/Sources/BrievieAPI/API_VERSION` (by `make sync-api`)
- Modify: `K/Sources/BrievieAPI/openapi-generator-config.yaml`
- Create: `K/Sources/BrievieCore/Documents/MyTaskModels.swift`, `K/Sources/BrievieCore/Documents/TaskAmount.swift`
- Modify: `K/Sources/BrievieCore/Documents/OrganiseModels.swift` (`WorkspaceTask`)
- Modify: `K/Sources/BrievieCore/Server/LiveBrievieServer+Tasks.swift` (`WorkspaceTask.init(task:)`)
- Test: `K/Tests/BrievieCoreTests/TaskAmountTests.swift` (new), `K/Tests/BrievieCoreTests/LiveBrievieServerTasksTests.swift`, `K/Tests/BrievieCoreTests/GeneratedContractTests.swift`

**Interfaces:**
- Produces (BrievieCore, all `public`, `Equatable, Sendable`):
  - `enum TaskGroup: String { case overdue, withinWeek = "within_week", later, noDate = "no_date", none = "", unknown }` with `init(api: String)` (unknown text → `.unknown`).
  - `enum TaskReason: String { case assigned, addressee, department, unassigned, other, none = "", unknown }` with `init(api: String)`.
  - `enum MyTasksPart: String { case mine, toPickUp = "to_pick_up", all }`; `enum MyTasksStatus: String { case open, done }`.
  - `WorkspaceTask` gains, each defaulted in `init` so every existing call site compiles: `deadlineSource: String = ""`, `deadlineQuote: String = ""`, `termQuote: String = ""`, `needsDeadline: Bool = false`, `amount: Decimal? = nil`, `daysLeft: Int? = nil`, `group: TaskGroup = .none`, `reason: TaskReason = .none`, `forNames: [String] = []`, `assignedToID: UUID? = nil`, `assignedToName: String = ""`, `assignedByName: String = ""`, `completedByName: String = ""`, `completedAt: Date? = nil`, `documentType: String = ""`, `canEdit: Bool? = nil` (nil = the server did not say: fall back to the role), `createdByAI: Bool = false`.
  - `enum TaskAmount { static func parse(api: String) -> Decimal?; static func api(_ amount: Decimal) -> String; static func parse(input: String, locale: Locale) -> Decimal? }`.

- [ ] **Step 1: Sync and widen the generator filter**

Run `make sync-api HOST=../Brievie_host` with `../Brievie_host` on `origin/main` at or after `24c0318`.
Add to `openapi-generator-config.yaml` under `filter.operations`, after `reopenTask`, with the comment
"Mijn taken (host PR #36)": `listMyTasks`, `countMyTasks`, `assignTask`, `listTaskAssignees`,
`setTaskDeadline`, `getMe`. Check: `cat K/Sources/BrievieAPI/API_VERSION` prints `1.0.0` (the server did not
bump it; the app finds the new endpoints by their 404, see Task 2).

- [ ] **Step 2: Write the failing tests**

`TaskAmountTests` (`@Suite struct TaskAmountTests`):

```swift
@Test func apiStringsParseLocaleFree() {
    #expect(TaskAmount.parse(api: "1234.56") == Decimal(string: "1234.56", locale: Locale(identifier: "en_US_POSIX")))
    #expect(TaskAmount.parse(api: "1234.5") == Decimal(string: "1234.50", locale: Locale(identifier: "en_US_POSIX")))
    #expect(TaskAmount.parse(api: "") == nil)
    #expect(TaskAmount.parse(api: "abc") == nil)
    #expect(TaskAmount.parse(api: "1,5") == nil)
}
@Test func amountsGoOutWithTwoDecimalsAndAPoint() {
    #expect(TaskAmount.api(Decimal(string: "1234.5", locale: Locale(identifier: "en_US_POSIX")) ?? 0) == "1234.50")
}
@Test(arguments: [("1.234,56", "nl_NL"), ("1234,56", "nl_NL"), ("€ 1.234,56", "nl_NL"), ("1,234.56", "en_GB"), ("1234.56", "en_US")])
func typedAmountsReadInTheUsersNotation(text: String, locale: String) {
    #expect(TaskAmount.parse(input: text, locale: Locale(identifier: locale)).map(TaskAmount.api) == "1234.56")
}
@Test func typedGarbageOrNegativeIsNil() {
    #expect(TaskAmount.parse(input: "twaalf", locale: Locale(identifier: "nl_NL")) == nil)
    #expect(TaskAmount.parse(input: "-5", locale: Locale(identifier: "nl_NL")) == nil)
    #expect(TaskAmount.parse(input: "", locale: Locale(identifier: "nl_NL")) == nil)
}
```

In `LiveBrievieServerTasksTests` add `openTasksDecodeTheMyTasksFields`: serve one `TaskItemOut` with every
new field (`"amount":"1234.56","days_left":-3,"group":"overdue","reason":"assigned","for_names":["Piet"],
"assigned_to_id":"<uuid>","assigned_to_name":"Anne","assigned_by_name":"Stijn","completed_by_name":"",
"term_quote":"","needs_deadline":false,"deadline_quote":"vóór 1 december","document_type":"tax_assessment",
"can_edit":true,"created_by_ai":false`) and expect each mapped value; and
`openTasksFromAnOlderServerKeepTheDefaults`: the fixture of `LiveBrievieServerBoundsTests.tasksJSON` (no new
fields) decodes with `amount == nil`, `group == .none`, `reason == .none`, `forNames == []`,
`canEdit == nil`. Add `group: "next_month"` → `.unknown` in a third test.

In `GeneratedContractTests` add `theMyTasksOperationsAreGenerated`: references
`Operations.ListMyTasks.self`, `Operations.CountMyTasks.self`, `Operations.AssignTask.self`,
`Operations.ListTaskAssignees.self`, `Operations.SetTaskDeadline.self`, `Operations.GetMe.self` (follow the
file's existing style for how it names generated types).

- [ ] **Step 3: Run the tests to see them fail**

Run: `swift test --package-path Packages/BrievieKit --filter "TaskAmountTests|LiveBrievieServerTasksTests|GeneratedContractTests"`
Expected: compile errors (`TaskAmount`, new `WorkspaceTask` members not defined).

- [ ] **Step 4: Implement**

`TaskAmount.parse(api:)`: `Decimal(string:locale: en_US_POSIX)`, only for text matching `^\d{1,10}(\.\d{1,2})?$`.
`api(_:)`: `formatted(.number.precision(.fractionLength(2)).grouping(.never).locale(en_US_POSIX))`.
`parse(input:locale:)`: strip spaces, `€` and the locale's grouping separator, then replace the locale's
decimal separator with `.`, then `parse(api:)`; negative or more than two decimals → nil.
`WorkspaceTask.init(task:)` maps every field; `assigned_to_id` that is not a UUID throws `.incompatible`
(like `document_id`); `completed_at` is the generated `Date?`.

- [ ] **Step 5: Run the tests to see them pass**

Run: `swift test --package-path Packages/BrievieKit --filter "TaskAmountTests|LiveBrievieServerTasksTests|GeneratedContractTests"`, then `make test` and `make lint`.
Expected: PASS; no other suite broke (all new `WorkspaceTask` parameters have defaults).

- [ ] **Step 6: Commit**

```bash
git add Packages/BrievieKit/Sources/BrievieAPI Packages/BrievieKit/Sources/BrievieCore Packages/BrievieKit/Tests/BrievieCoreTests
git commit -m "feat(api): sync the Mijn taken API and decode the new task fields"
```

---

### Task 2: The six calls through the seam

**Files:**
- Create: `K/Sources/BrievieCore/Server/LiveBrievieServer+MyTasks.swift`
- Modify: `K/Sources/BrievieCore/Documents/DocumentModels.swift` (protocol `DocumentServer` + its extension)
- Modify: `K/Sources/BrievieCore/Documents/WorkspaceDocuments.swift`
- Modify: `K/Sources/BrievieCore/Server/ServerError+Mapping.swift`
- Modify: `K/Sources/BrievieCore/Documents/FakeDocumentServer.swift`, `K/Tests/FeatureDocumentsTests/GatedDocumentServer.swift`
- Test: `K/Tests/BrievieCoreTests/LiveBrievieServerMyTasksTests.swift` (new), `K/Tests/BrievieCoreTests/WorkspaceDocumentsTests.swift`, `K/Tests/BrievieCoreTests/LiveBrievieServerBoundsTests.swift`

**Interfaces:**
- Consumes: Task 1's types.
- Produces:
  - `public struct MyTasks { items: [WorkspaceTask]; today: CalendarDate; hasPerson: Bool; truncated: Bool; waitingLetters: Int; split: Bool }` (in `MyTaskModels.swift`).
  - `public struct MyTaskCounts { mine, overdue, withinWeek, needsDate, toPickUp: Int }`.
  - `public struct TaskAssignee: Identifiable { id: UUID (user id); name: String; isMe: Bool }`.
  - `DocumentServer` gains, each with a protocol-extension default `throw ServerError.other("http_404")` (the `search` precedent, so test servers compile):
    `myTasks(part: MyTasksPart, status: MyTasksStatus, in: DocumentScope) async throws -> MyTasks`,
    `myTaskCounts(in:) async throws -> MyTaskCounts`,
    `assignTask(_ id: UUID, to user: UUID?, in:) async throws -> WorkspaceTask`,
    `taskAssignees(_ id: UUID, in:) async throws -> [TaskAssignee]`,
    `setTaskDeadline(_ id: UUID, to deadline: CalendarDate?, in:) async throws -> WorkspaceTask`,
    `currentUserID(in:) async throws -> UUID` (`getMe`, only `id` is read; nothing else of `UserOut` is kept).
  - `WorkspaceDocuments` gains the same six without `in:` and `throws(DocumentsError)`, plus `public var userName: String { connection.userName }`.
  - `DocumentsError` gains `.assigneeCannotRead` and `.taskWithoutLetter`.

- [ ] **Step 1: Write the failing tests**

`LiveBrievieServerMyTasksTests` (StubURLProtocol, like `LiveBrievieServerTasksTests`):

```swift
@Test func myTasksSendsPartAndStatusAndDecodesTheWrapper() async throws {
    // serve {"items":[<task>],"today":"2026-11-21","has_person":true,"truncated":false,"waiting_letters":3,"split":true}
    let answer = try await server.myTasks(part: .toPickUp, status: .open, in: scope(url))
    #expect(StubURLProtocol.lastRequest?.url?.query()?.contains("part=to_pick_up") == true)
    #expect(StubURLProtocol.lastRequest?.url?.query()?.contains("status=open") == true)
    #expect(answer.today == CalendarDate(year: 2026, month: 11, day: 21))
    #expect(answer.waitingLetters == 3 && answer.split && answer.hasPerson && !answer.truncated)
}
@Test func countsDecode() async throws { /* {"mine":4,"overdue":1,"within_week":2,"needs_date":1,"to_pick_up":0} */ }
@Test func assignSendsTheUserOrNullToRelease() async throws {
    // body of assignTask(id, to: user) is {"user_id":"<uuid>"}; to: nil sends {"user_id":null}
}
@Test func assigneeCannotReadPassesThrough() async throws {
    // 422 {"code":"assignee_cannot_read","message":"..."} -> ServerError.other("assignee_cannot_read")
}
@Test func setDeadlineSendsTheIsoDateOrNull() async throws { /* {"deadline":"2026-12-01"} and {"deadline":null} */ }
@Test func currentUserIDReadsOnlyTheID() async throws { /* getMe answer -> the UUID */ }
@Test func myTasksOnAnOlderServerIsNotSupported() async throws {
    // 404 with a non-Brievie body -> WorkspaceDocuments.myTasks(...) throws .notSupported
}
```

In `WorkspaceDocumentsTests` add `assignmentCodesBecomeTheirOwnErrors`: a `FakeDocumentServer` throwing
`.other("assignee_cannot_read")` → `.assigneeCannotRead`; `.other("task_without_letter")` →
`.taskWithoutLetter`; `.other("task_not_found")` → `.notFound`; `.other("validation_error")` → `.invalid`.
In `LiveBrievieServerBoundsTests` add `aMyTasksAnswerAboveTheCapIsRefused` (same shape as the existing
`aJSONAnswerAboveTheCapIsRefused`).

- [ ] **Step 2: Run to see them fail**

Run: `swift test --package-path Packages/BrievieKit --filter "LiveBrievieServerMyTasksTests|WorkspaceDocumentsTests|LiveBrievieServerBoundsTests"`
Expected: compile errors (methods not defined).

- [ ] **Step 3: Implement**

`LiveBrievieServer+MyTasks.swift`: one method per operation, the `switch output` shape of
`LiveBrievieServer+Tasks.swift` (every documented status → `ServerError(status:code:)`,
`.undocumented` → `ServerError(status:code: nil)`). `MyTasks.today` that is not an ISO date throws
`.incompatible`. Add `"assignee_cannot_read"` and `"task_without_letter"` to
`ServerError.passThroughCodes`; map them in `WorkspaceDocuments.verdict`. `FakeDocumentServer`: `Call` cases
`myTasks(URL, MyTasksPart, MyTasksStatus)`, `myTaskCounts(URL)`, `assignTask(URL, UUID, UUID?)`,
`taskAssignees(URL, UUID)`, `setTaskDeadline(URL, UUID, CalendarDate?)`, `currentUserID(URL)`, with settable
answers (default: `MyTasks` with empty items, today 2026-11-21, `hasPerson: true`, `split: false`; counts all
zero; `assignTask` echoes a task with `assignedToID` set; assignees `[]`; me a fixed UUID).
`GatedDocumentServer`: forwarders to `inner`.

- [ ] **Step 4: Run to see them pass**

Run: the filter of Step 2, then `make test` and `make lint`. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Packages/BrievieKit
git commit -m "feat(core): list, count, assign and date tasks through the server seam"
```

---

### Task 3: The words of a task row

**Files:**
- Create: `K/Sources/FeatureDocuments/TaskWords.swift`, `K/Sources/FeatureDocuments/DocumentStrings+MyTasks.swift`
- Modify: `K/Sources/FeatureDocuments/Resources/Localizable.xcstrings`, `docs/GLOSSARY-en.md`
- Test: `K/Tests/FeatureDocumentsTests/TaskWordsTests.swift` (new)

**Interfaces:**
- Consumes: `WorkspaceTask` (Task 1).
- Produces `enum TaskWords` (internal, static, pure; `locale` parameters default to `.autoupdatingCurrent`):
  - `when(_ task: WorkspaceTask, locale:) -> String?` — "Vandaag", "Morgen", "Nog 5 dagen (1 dec)", "1 dag te laat (20 nov)", "3 dagen te laat (18 nov)"; nil without `deadline` or `daysLeft`.
  - `isLate(_ task:) -> Bool` — `daysLeft < 0`.
  - `groupTitle(_ group: TaskGroup) -> String?` — nil for `.none` / `.unknown`.
  - `amount(_ task:, locale:) -> String?` — `Decimal.formatted(.currency(code: "EUR").locale(locale))`.
  - `whose(_ task:, me: String) -> String?` — the rules of `web/src/task-time.ts` `forText`: `assigned` → "Jij doet dit" when `assignedByName` is empty or `me`, else "Aan jou gegeven door Anne"; `addressee` → "Voor jou" / "Voor jou en Piet"; `department` → "Voor Finance" (the names); `unassigned` → "Voor Piet" or "Zonder naam"; otherwise "Bij Anne" (assignee) or "Voor Piet" or nil. Names joined with the system list format (`.list(type: .and)`), as `DocumentsModel.Row.addresseeLine` does.
  - `fromFor(_ task:, me:) -> String?` — "Van Belastingdienst · Voor jou"; either part may be absent.
  - `why(_ task:) -> String?` — "Uit de brief: ‘<deadline_quote>’" for `deadlineSource == "in_document"` with a quote and a deadline; "Datum zelf ingevuld" for `manual` with a deadline; else nil.
  - `needsDate(_ task:) -> String?` — when `needsDeadline`: "De brief noemt een termijn: ‘<term>’. Vul de datum in." (without the quote part when `termQuote` is empty: "Vul de datum in.").
  - `typeWord(_ task:) -> String?` — `DocumentTypes.taskTypeLabel(type)` unless the description already starts with it (case-insensitive).
  - `doneLine(_ task:, locale:) -> String?` — "Afgevinkt door Anne op 20 nov" / "Afgevinkt op 20 nov" (from `completedAt` in the phone's time zone; nil without it).
  - `tickLabel(_ task:) -> String` — "Klaar: <description>"; `accessibilityLabel(_ task:, me:, locale:) -> String` — action, when, amount, from/for, why, needs-date, joined with ", ".

Dates in these words: `CalendarDate` formatted day + abbreviated month in `locale` (noon of the day in the
phone's zone, so no zone moves the day).

- [ ] **Step 1: Write the failing tests**

`TaskWordsTests` with a helper `task(daysLeft:deadline:...) -> WorkspaceTask` and `nl = Locale(identifier: "nl_NL")`:

```swift
@Test func whenWordsFollowTheServersDaysLeft() {
    #expect(TaskWords.when(task(daysLeft: 0, deadline: "2026-11-21"), locale: nl) == "Vandaag")
    #expect(TaskWords.when(task(daysLeft: 1, deadline: "2026-11-22"), locale: nl) == "Morgen")
    #expect(TaskWords.when(task(daysLeft: 10, deadline: "2026-12-01"), locale: nl) == "Nog 10 dagen (1 dec)")
    #expect(TaskWords.when(task(daysLeft: -1, deadline: "2026-11-20"), locale: nl) == "1 dag te laat (20 nov)")
    #expect(TaskWords.when(task(daysLeft: -3, deadline: "2026-11-18"), locale: nl) == "3 dagen te laat (18 nov)")
    #expect(TaskWords.when(task(daysLeft: nil, deadline: nil), locale: nl) == nil)
}
@Test func lateIsAlsoInWords() { /* isLate true for -1 and the when text contains "te laat" */ }
@Test func groupTitlesInOrder() {
    #expect([TaskGroup.overdue, .withinWeek, .later, .noDate].compactMap(TaskWords.groupTitle)
        == ["Te laat", "Binnen 7 dagen", "Later", "Zonder datum"])
    #expect(TaskWords.groupTitle(.unknown) == nil)
}
@Test func amountIsEurosInTheUsersLocale() {
    #expect(TaskWords.amount(task(amount: "1234.56"), locale: nl) == "€ 1.234,56")
    #expect(TaskWords.amount(task(amount: nil), locale: nl) == nil)
}
@Test func whoseFollowsTheReason() {
    #expect(TaskWords.whose(task(reason: .assigned, assignedBy: "Anne"), me: "Stijn") == "Aan jou gegeven door Anne")
    #expect(TaskWords.whose(task(reason: .assigned, assignedBy: "Stijn"), me: "Stijn") == "Jij doet dit")
    #expect(TaskWords.whose(task(reason: .addressee, forNames: ["Piet"]), me: "Stijn") == "Voor jou en Piet")
    #expect(TaskWords.whose(task(reason: .unassigned), me: "Stijn") == "Zonder naam")
    #expect(TaskWords.whose(task(reason: .other, assignedTo: "Anne"), me: "Stijn") == "Bij Anne")
}
@Test func whySaysWhereTheDateCameFrom() { /* in_document + quote; manual; no deadline -> nil */ }
@Test func needsDateQuotesTheTerm() { /* "De brief noemt een termijn: ‘binnen zes weken na dagtekening’. Vul de datum in." */ }
@Test func theTickBoxIsNamedAfterTheAction() { #expect(TaskWords.tickLabel(task(description: "Betaal de aanslag")) == "Klaar: Betaal de aanslag") }
@Test func everyMyTasksKeyHasADutchValue() throws { /* CatalogParity.dutchValue for each key of DocumentStrings+MyTasks */ }
```

(The `nl` expectations read the catalog's Dutch values: write them in Step 3 before running Step 4. Plural
keys `tasks.when.daysLeft` and `tasks.when.late` carry `one` and `other`.)

- [ ] **Step 2: Run to see them fail**

Run: `swift test --package-path Packages/BrievieKit --filter TaskWordsTests`
Expected: compile error (`TaskWords` not defined).

- [ ] **Step 3: Implement `TaskWords`, the strings and the glossary**

Keys in `DocumentStrings+MyTasks.swift` (prefix `tasks.`), Dutch default values as in the spec, English from
the host's `web/src/locales/en/messages.po` (it already holds every sentence below), for example: "Vandaag" /
"Today", "Morgen" / "Tomorrow", "Nog %d dagen (%@)" / "%d days left (%@)", "%d dag te laat (%@)" /
"%d day overdue (%@)" (plural), "Te laat" / "Overdue", "Binnen 7 dagen" / "Within 7 days", "Later" /
"Later", "Zonder datum" / "No date", "Van %@" / "From %@", "Voor jou" / "For you", "Voor jou en %@" /
"For you and %@", "Voor %@" / "For %@", "Zonder naam" / "No name", "Bij %@" / "With %@", "Jij doet dit" /
"You are doing this", "Aan jou gegeven door %@" / "Handed to you by %@", "Uit de brief: ‘%@’" /
"From the letter: ‘%@’", "Datum zelf ingevuld" / "Date filled in by hand", "Datum nodig" / "Needs a date",
"De brief noemt een termijn: ‘%@’. Vul de datum in." / "The letter names a deadline: ‘%@’. Fill in the
date.", "Klaar: %@" / "Done: %@", "Afgevinkt door %1$@ op %2$@" / "Ticked off by %1$@ on %2$@",
"Afgevinkt op %@" / "Ticked off on %@". Every key gets a `comment` saying where it shows.
`docs/GLOSSARY-en.md`: add rows Mijn taken / My tasks; Op te pakken / To pick up; Alle taken / All tasks;
Afgerond, Afgevinkt door / Done, Ticked off by ("Toch niet klaar": "Not done after all"); Datum nodig, Datum
invullen / Needs a date, Set a date; Ik doe dit / I'll do it; Geef aan…, Niet meer aan mij / Hand over…, Not
mine any more; and change the row "Te doen | To do" to "Inbox | Inbox" only if PR #24 did not already.

- [ ] **Step 4: Run to see them pass**

Run: `swift test --package-path Packages/BrievieKit --filter "TaskWordsTests|EnglishCatalogTests|CatalogKeyCoverageTests"`, then `make lint`.
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Packages/BrievieKit/Sources/FeatureDocuments Packages/BrievieKit/Tests/FeatureDocumentsTests docs/GLOSSARY-en.md
git commit -m "feat(tasks): words for a task row in Dutch and English"
```

---

### Task 4: `MyTasksModel`: load, groups, tick and undo, Afgerond

**Files:**
- Create: `K/Sources/FeatureDocuments/MyTasksModel.swift`
- Modify: `K/Sources/FeatureDocuments/DocumentStrings+MyTasks.swift`, `Resources/Localizable.xcstrings`
- Test: `K/Tests/FeatureDocumentsTests/MyTasksModelTests.swift` (new)

**Interfaces:**
- Consumes: `WorkspaceDocuments.myTasks`, `.completeTask`, `.reopenTask`, `.userName` (Task 2); `TaskWords` (Task 3).
- Produces `@MainActor @Observable public final class MyTasksModel`:
  - `init(documents: WorkspaceDocuments, canEdit: Bool, onTasksChanged: @escaping @MainActor () -> Void, onShowInbox: @escaping @MainActor () -> Void, onRevoked: @escaping @MainActor () -> Void, onMissingPairing: @escaping @MainActor () -> Void)`.
  - `enum State { case loading, loaded, failed(message: String), notSupported }`; `enum Filter { case mine, all }`; `enum Tab { case open, done }`.
  - `struct Row: Identifiable, Equatable` — `id`, `documentID: UUID?`, `title` (description), `typeWord: String?`, `when: String?`, `isLate: Bool`, `amount: String?`, `fromFor: String?`, `why: String?`, `needsDate: String?`, `doneLine: String?`, `isTicked: Bool`, `canTick: Bool`, `canTakeOn: Bool`, `canRelease: Bool`, `canHandOver: Bool`, `canSetDate: Bool`, `tickLabel: String`, `accessibilityLabel: String`. (Action flags are filled in Task 5; here they are `false`.)
  - `struct Section: Identifiable` — `id: TaskGroup`, `title: String`, `count: Int`, `rows: [Row]`.
  - Read-only state: `state`, `filter`, `tab`, `sections: [Section]` (open tab), `toPickUp: Section?` (only when `split` and `filter == .mine`, title "Op te pakken"), `doneRows: [Row]` (done tab), `description: String` (home / business sentence by `split`), `waitingLine: String?` ("Er wacht nog 1 brief op nakijken…" / "Er wachten nog %d brieven…", nil at 0), `noPersonNotice: String?`, `viewerNotice: String?`, `truncatedNote: String?`, `emptyText: String?`, `actionError: String?`, `announcement: String?` (for VoiceOver: "Afgevinkt: …" / "Weer open: …").
  - `func load() async`, `func select(_ filter: Filter) async`, `func select(_ tab: Tab) async`, `func setDone(_ done: Bool, for id: UUID) async`, `func showInbox()` (calls `onShowInbox`), `func leave()` (drops struck-through rows: called when the screen disappears).

Rules the tests pin:
- Open tab loads `myTasks(part: filter == .mine ? .mine : .all, status: .open)`; when the answer has
  `split` and `filter == .mine`, also `myTasks(part: .toPickUp, status: .open)` (the second call after the
  first answer, since only that answer says `split`; one failure fails the load). Done tab loads `myTasks(part: filter…, status: .done)`.
- Sections in the order overdue, withinWeek, later, noDate; empty groups are left out; rows keep the
  server's order; a task with `group == .unknown` or `.none` goes to "Zonder datum" when it has no deadline,
  else "Later" (never dropped).
- `canTick` = `canEdit && task.canEdit != false`.
- A tick is optimistic (row `isTicked` at once), sent in order like `ConfirmedDocumentModel.send`; on
  success the row stays in place struck through and `onTasksChanged()` is called; on failure it flips back
  and `actionError` is "Dat lukte niet. Probeer het opnieuw." (reuse `DocumentStrings.changeFailed`); on
  `.notFound` the row is removed and the list reloads without an error; `.revoked` / `.missingPairing` call
  their closures. Unticking a struck row ("Ongedaan maken") calls `reopenTask`.
- `load()` (pull to refresh, tab or filter change) drops struck rows: the server no longer lists them.
- A failed first load: `.failed(message: DocumentsModel.message(for:))`; a failed reload keeps the list on
  screen and shows the message as `actionError` (as `TrashModel.load` does). `.notSupported` → state
  `.notSupported` (the screen says the server is older: "Je server kent Mijn taken nog niet. Werk Brievie op
  de server bij.").

- [ ] **Step 1: Write the failing tests**

`MyTasksModelTests` (`@MainActor @Suite`), with a `FakeDocumentServer` and the model factory of
`DocumentsInboxTickTests`. Names and what each asserts:

- `loadsMineOpenAndGroupsInOrder` — items with groups later, overdue, noDate, withinWeek → section ids `[.overdue, .withinWeek, .later, .noDate]`, counts right; the fake recorded `.myTasks(url, .mine, .open)`.
- `toPickUpOnlyForAnOrganisation` — `split: false` → `toPickUp == nil` and no `.toPickUp` call; `split: true` → `toPickUp?.title == "Op te pakken"`; with zero rows its `rows` is empty and the view's text is "Er ligt niets op te pakken.".
- `allTasksFilterAsksForAllAndHidesToPickUp` — `select(.all)` records `.myTasks(url, .all, .open)`; `toPickUp == nil`.
- `doneTabListsTickedOffWithWho` — `select(.done)` → `doneRows[0].doneLine == "Afgevinkt door Anne op 20 nov"` (nl).
- `tickKeepsTheRowStruckAndUndoReopens` — `setDone(true, for:)` → row `isTicked`, still in `sections`, `.completeTask` recorded, `onTasksChanged` called once, `announcement == "Afgevinkt: Betaal de aanslag"`; `setDone(false, for:)` → `.reopenTask` recorded, row not ticked.
- `refreshDropsStruckRows` — tick, then `load()` with the server no longer listing it → row gone.
- `failedTickFlipsBack` — `completeTask` throws `.unreachable` → row not ticked, `actionError` set.
- `tickOnAVanishedTaskRemovesTheRow` — `completeTask` throws `.other("task_not_found")` → row gone, `actionError == nil`, a reload was recorded.
- `viewerGetsNoActions` — `canEdit: false` → every row `canTick == false`, `viewerNotice == "Je kunt taken bekijken, maar niet afvinken."`; with `canEdit: true` and a task `canEdit: false` that row cannot tick; `canEdit: nil` (older server) follows the role.
- `memberWithoutPersonIsTold` — `hasPerson: false` with filter `.mine` → `noPersonNotice` is the spec S 9 sentence; with `.all` → nil.
- `waitingLettersLineLinksToTheInbox` — `waitingLetters: 3` → "Er wachten nog 3 brieven op nakijken. Daar kunnen nieuwe taken uit komen."; `showInbox()` calls `onShowInbox`; `0` → nil.
- `truncatedListSaysSoAndKeepsServerCounts` — `truncated: true` → `truncatedNote == "Alleen de eerste 500 taken worden getoond."`.
- `emptyOpenListExplainsItself` — no items → `emptyText == "Je hebt geen open taken. Nieuwe taken komen hier vanzelf zodra je post is nagekeken."`; done tab empty → "Je hebt de laatste 30 dagen niets afgevinkt.".
- `olderServerIsNotSupported` — `myTasks` throws `.other("http_404")` → `state == .notSupported`.
- `failedReloadKeepsTheList` — first load ok, second `.unreachable` → `state == .loaded`, rows kept, `actionError` set.
- `aStaleAnswerNeverOverwritesANewerOne` — gate the first `myTasks` (`GatedDocumentServer`), switch filter, release → rows of the second answer.

- [ ] **Step 2: Run to see them fail**

Run: `swift test --package-path Packages/BrievieKit --filter MyTasksModelTests`
Expected: compile error (`MyTasksModel` not defined).

- [ ] **Step 3: Implement `MyTasksModel` and its strings**

New keys (nl / en from the host catalogue): title "Mijn taken" / "My tasks"; filter "Mijn taken" / "Alle
taken"; tabs "Open" / "Afgerond" ("Open" / "Done"); the two descriptions of spec S 13; "Op te pakken" / "To
pick up"; the empty texts, the no-person, viewer, truncated and waiting-letters sentences above; "Naar
Inbox" / "Go to Inbox"; "Ongedaan maken" / "Undo"; "Toch niet klaar" / "Not done after all"; "Afgevinkt:
%@" / "Ticked off: %@"; "Weer open: %@" / "Open again: %@"; "Je server kent Mijn taken nog niet. Werk
Brievie op de server bij." / "Your server does not know My tasks yet. Update Brievie on the server.". A load
counter (like `DocumentsModel.owns`) drops answers of an older load.

- [ ] **Step 4: Run to see them pass**

Run: `swift test --package-path Packages/BrievieKit --filter "MyTasksModelTests|EnglishCatalogTests|CatalogKeyCoverageTests"`, then `make lint`.
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Packages/BrievieKit/Sources/FeatureDocuments Packages/BrievieKit/Tests/FeatureDocumentsTests
git commit -m "feat(tasks): the Mijn taken model with groups, ticking and Afgerond"
```

---

### Task 5: Ik doe dit, Niet meer aan mij, Geef aan…, Datum invullen

**Files:**
- Create: `K/Sources/FeatureDocuments/MyTasksModel+Actions.swift`
- Modify: `K/Sources/FeatureDocuments/MyTasksModel.swift` (action flags on `Row`), `DocumentStrings+MyTasks.swift`, `Resources/Localizable.xcstrings`
- Test: `K/Tests/FeatureDocumentsTests/MyTasksActionsTests.swift` (new)

**Interfaces:**
- Consumes: `WorkspaceDocuments.assignTask`, `.taskAssignees`, `.setTaskDeadline`, `.currentUserID` (Task 2); `MyTasksModel` (Task 4).
- Produces on `MyTasksModel`:
  - `enum Sheet: Identifiable, Equatable { case handOver(taskID: UUID, title: String, people: [TaskAssignee]); case setDate(taskID: UUID, title: String, term: String?, current: CalendarDate?) }`; `public var sheet: Sheet?`; `public private(set) var sheetError: String?`.
  - `func takeOn(_ id: UUID) async` — "Ik doe dit": `currentUserID()` once per model (cached), then `assignTask(id, to: me)`.
  - `func release(_ id: UUID) async` — "Niet meer aan mij": `assignTask(id, to: nil)`.
  - `func startHandOver(_ id: UUID) async` — loads `taskAssignees(id)` (without `isMe`), opens `.handOver`; an empty answer opens it with the text "Er is niemand anders die deze brief mag lezen.".
  - `func handOver(_ id: UUID, to user: UUID) async`, `func startSettingDate(_ id: UUID)`, `func setDate(_ date: CalendarDate?, for id: UUID) async`, `func closeSheet()`.
- Row flags (all also require `canTick`): `canTakeOn` = `reason` is `department`/`unassigned`/`other` with no assignee, or `addressee`, and not ticked; `canRelease` = `reason == .assigned`; `canHandOver` = `documentID != nil`; `canSetDate` = `deadline == nil` (the "Datum nodig" rows show it prominently, others in the row's menu).

After every successful action: `onTasksChanged()` and `load()` (the task may change section or leave the
list: the server decides). Errors: `.assigneeCannotRead` → `sheetError = "Deze persoon mag de brief niet
lezen. Kies iemand anders."` and the assignees reload; `.taskWithoutLetter` → `actionError = "Deze taak
hoort niet bij een brief en kan niet worden gegeven."`; `.invalid` on a date → `sheetError = "Die datum ligt
voor de datum van de brief."`; `.notFound` → reload quietly, sheet closed; others → `actionError` /
`sheetError` "Dat lukte niet. Probeer het opnieuw.".

- [ ] **Step 1: Write the failing tests**

`MyTasksActionsTests`:
- `takeOnAssignsToMeAndReloads` — records `.currentUserID`, `.assignTask(url, id, me)`, then a `.myTasks` load; `onTasksChanged` called; a second `takeOn` does not call `currentUserID` again.
- `releaseSendsNull` — `.assignTask(url, id, nil)`.
- `handOverListsOnlyWhatTheServerGives` — assignees `[me, Anne]` → sheet people `[Anne]`; `handOver(id, to: anne)` records `.assignTask(url, id, anne)` and closes the sheet.
- `handOverToSomeoneWhoCannotReadSaysSo` — throws `.other("assignee_cannot_read")` → `sheetError` is the sentence, sheet stays open.
- `setDateSendsTheDayAndMovesTheTask` — `setDate(2026-12-01)` records `.setTaskDeadline(url, id, 2026-12-01)` and reloads.
- `dateBeforeTheLetterIsRefusedInWords` — throws `.other("validation_error")` → `sheetError == "Die datum ligt voor de datum van de brief."`.
- `takeOnAVanishedTaskReloads` — `.other("task_not_found")` → no `actionError`, reload recorded.
- `actionFlagsFollowReasonAndRole` — table over reasons × `canEdit` for `canTakeOn`/`canRelease`/`canHandOver`/`canSetDate`.

- [ ] **Step 2: Run to see them fail**

Run: `swift test --package-path Packages/BrievieKit --filter MyTasksActionsTests`
Expected: compile errors.

- [ ] **Step 3: Implement the actions and their strings**

New keys: "Ik doe dit" / "I'll do it"; "Niet meer aan mij" / "Not mine any more"; "Geef aan…" / "Hand
over…"; "Aan wie geef je deze taak?" / "Who do you hand this task to?"; "Alleen wie deze brief mag lezen,
staat in de lijst." / "Only people who may read this letter are in the list."; "Datum invullen" / "Set a
date"; "Welke datum noemt de brief?" / "Which date does the letter name?"; the error sentences above (English
from the host catalogue); accessibility labels "Ik doe dit: %@", "Niet meer aan mij: %@", "Geef aan: %@",
"Datum invullen: %@", "Brief bekijken: %@", "Toch niet klaar: %@" (English likewise).

- [ ] **Step 4: Run to see them pass**

Run: `swift test --package-path Packages/BrievieKit --filter "MyTasksActionsTests|MyTasksModelTests|EnglishCatalogTests|CatalogKeyCoverageTests"`, then `make lint`.
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Packages/BrievieKit/Sources/FeatureDocuments Packages/BrievieKit/Tests/FeatureDocumentsTests
git commit -m "feat(tasks): pick up, hand over, release and date a task"
```

---

### Task 6: The Mijn taken screen

**Files:**
- Create: `K/Sources/FeatureDocuments/MyTasksView.swift`, `MyTaskRowView.swift`, `MyTaskSheets.swift` (all `#if os(iOS)`)
- Test: none new (views are dumb; their state is tested in Tasks 4–5); `#Preview`s with `FakeDocumentServer` for: loaded home, loaded organisation with "Op te pakken", viewer, no person, empty, failed, dark mode, largest Dynamic Type (`.dynamicTypeSize(.accessibility5)`).

**Interfaces:**
- Consumes: `MyTasksModel` (Tasks 4–5).
- Produces:
  - `public struct MyTasksView<Destination: View>: View` — `init(model: MyTasksModel, @ViewBuilder destination: @escaping (UUID) -> Destination)` (the letter screen, as `DocumentsView` passes it).
  - `struct MyTaskRowView<Badge: View>: View` — `init(row: MyTasksModel.Row, tick: @escaping (Bool) -> Void, actions: MyTaskRowActions, @ViewBuilder badge: () -> Badge = { EmptyView() })`. The badge slot is where the later letter-status design puts its badge; nothing fills it now.
  - `struct MyTaskRowActions` — closures `takeOn`, `release`, `handOver`, `setDate`, `openLetter` (each optional; nil hides it).

Layout and behaviour:
- A `List` (`.insetGrouped`): description; notices (`ErrorBanner` `.warning` for viewer / no person / not
  supported, `.error` with "Opnieuw proberen" for a failed load — the same as `DocumentsList`'s failed
  state); the waiting line with a "Naar Inbox" button; a segmented `Picker` "Open / Afgerond" and a second
  one "Mijn taken / Alle taken"; one `Section` per group with header "<titel> (<aantal>)" marked
  `.accessibilityAddTraits(.isHeader)`; "Op te pakken" as the last section; the truncated note under it.
- Row: leading tick button (`circle` / `checkmark.circle.fill`, 44 pt hit area, `accessibilityLabel` =
  `tickLabel`, `accessibilityValue` open/klaar), then title (`.headline`, struck through when ticked), type
  word, when (`Color.orange` + `exclamationmark.triangle` symbol when `isLate`, the words always there),
  amount, from/for, why, "Datum nodig" capsule + needs-date sentence + "Datum invullen" button, done line.
  The row is one VoiceOver element (`accessibilityElement(children: .combine)` with `accessibilityLabel`)
  whose actions are `accessibilityActions`: tick/untick, Ik doe dit, Niet meer aan mij, Geef aan…, Datum
  invullen, Brief bekijken (the `TaskTickRow` pattern of `ConfirmedDocumentSections.swift`).
- Swipe (leading, `allowsFullSwipe`): "Klaar" (or "Ongedaan maken" when ticked), only when `canTick`.
  Trailing swipe / context menu: the other actions that the row allows.
- A ticked row shows an inline "Ongedaan maken" button; `model.announcement` is posted with
  `AccessibilityNotification.Announcement` when it changes.
- "Brief bekijken" pushes `destination(documentID)`.
- Sheets: `HandOverSheet` (list of names, intro "Alleen wie deze brief mag lezen, staat in de lijst.", the
  `sheetError` as `ErrorBanner`); `SetDateSheet` (`DatePicker` graphical, the term quote above it, "Opslaan"
  / "Annuleren", "Datum weghalen" when there is one). Sheets close themselves on `scenePhase != .active`
  (like the review's).
- `.refreshable { await model.load() }`, `.task { await model.load() }`, `.onDisappear { model.leave() }`.
- No literal strings: every text comes from the model or `DocumentStrings`.

- [ ] **Step 1: Build the views**
- [ ] **Step 2: Check: `make build` succeeds and `make lint` is clean**
- [ ] **Step 3: Check the previews by hand in Xcode: VoiceOver rotor reads "Klaar: Betaal de aanslag", the late row says "te laat" in words, the largest text size wraps without clipping**
- [ ] **Step 4: Commit**

```bash
git add Packages/BrievieKit/Sources/FeatureDocuments
git commit -m "feat(tasks): the Mijn taken screen with rows, sheets and VoiceOver actions"
```

---

### Task 7: "Mijn taken" next to the Inbox

**Files:**
- Create: `K/Sources/FeatureDocuments/DocumentsModel+MyTasks.swift`
- Modify: `K/Sources/FeatureDocuments/DocumentsModel.swift` (load counts with the inbox counts), `DocumentsView.swift` (menu entry, content switch, title), `DocumentsList.swift` (Inbox link row), `DocumentStrings+MyTasks.swift`, `Resources/Localizable.xcstrings`
- Modify: `App/RootView.swift` (`DocumentsScreen`: pass the letter destination, nothing else)
- Test: `K/Tests/FeatureDocumentsTests/DocumentsMyTasksTests.swift` (new)

**Interfaces:**
- Consumes: `MyTasksModel`, `MyTasksView` (Tasks 4–6); `WorkspaceDocuments.myTaskCounts` (Task 2).
- Produces on `DocumentsModel`:
  - `public var isShowingMyTasks: Bool` (the trash's `isShowingTrash` pattern), `public internal(set) var myTaskCounts: MyTaskCounts?` (nil: not loaded or an older server), `public internal(set) var hasMyTasks: Bool` (false after a `.notSupported`).
  - `public func showMyTasks()`, `public func showInbox() async` (sets `isShowingMyTasks = false` and selects `.inbox`), `public func makeMyTasksModel() -> MyTasksModel` (passes `canScan` as `canEdit`, `onTasksChanged`, `onShowInbox: showInbox`, the revoke closures).
  - `public var myTasksMenuTitle: String` — "Mijn taken", with the count in words when known: "Mijn taken · 4 open" / "Mijn taken · 4 open, 1 te laat" (a menu shows no colour, so the words carry it).
  - `public var myTasksLink: MyTasksLink?` — `struct MyTasksLink { text: String; isLate: Bool }` for a row on top of the Inbox: "Mijn taken: 4 open" / "Mijn taken: 4 open, waarvan 1 te laat"; nil when `mine == 0` or counts unknown. `isLate` → warning colour and symbol in `DocumentsList`.
  - Selecting any scope sets `isShowingMyTasks = false`.
- Counts load in `DocumentsModel.load()` next to `inboxCounts` (a failure keeps the old value; `.notSupported` sets `hasMyTasks = false`), and again after `onTasksChanged`.

View wiring in `DocumentsView`: in `scopeMenu`'s `Section`, above the `Picker`, a `Button` with
`myTasksMenuTitle` and `systemImage: "checklist"` (checkmark state when shown), only when `hasMyTasks`.
`content` shows `MyTasksView(model: myTasksModel, destination: destination)` when `isShowingMyTasks`
(model kept in `@State`, made by `makeMyTasksModel()` on first show, like `trashModel`); search and letter
polling are off while it shows; the navigation title is "Mijn taken". The scan button stays. The start
screen stays the Inbox. `DocumentsList` gets an optional `myTasksLink` row at the top of the Inbox scope
(button → `showMyTasks()`, `accessibilityLabel` = the text, plus "te laat" in words when `isLate`).

- [ ] **Step 1: Write the failing tests**

`DocumentsMyTasksTests`:
- `loadReadsTheCountsWithTheInbox` — `load()` records `.myTaskCounts`; `myTasksMenuTitle == "Mijn taken · 4 open, 1 te laat"` for `mine: 4, overdue: 1`.
- `inboxLinkSaysLateInWords` — `myTasksLink == MyTasksLink(text: "Mijn taken: 4 open, waarvan 1 te laat", isLate: true)`; `mine: 0` → nil.
- `menuHidesMyTasksOnAnOlderServer` — counts throw `.other("http_404")` → `hasMyTasks == false`; the inbox still loads.
- `pickingAScopeLeavesMyTasks` — `showMyTasks()`, then `select(.all)` → `isShowingMyTasks == false`.
- `myTasksShowInboxGoesBackToTheInbox` — the made model's `showInbox()` → `isShowingMyTasks == false`, `scope == .inbox`.
- `theStartScreenIsStillTheInbox` — a new model: `isShowingMyTasks == false`, `scope == .inbox`.
- `aTickInMyTasksRefreshesTheCounts` — tick through the made model → `.myTaskCounts` recorded again and `onTasksChanged` called.

- [ ] **Step 2: Run to see them fail**

Run: `swift test --package-path Packages/BrievieKit --filter DocumentsMyTasksTests`
Expected: compile errors.

- [ ] **Step 3: Implement, with the strings** ("Mijn taken · %d open" / "My tasks · %d open"; "Mijn taken · %1$d open, %2$d te laat" / "My tasks · %1$d open, %2$d overdue"; "Mijn taken: %d open" / "My tasks: %d open"; "Mijn taken: %1$d open, waarvan %2$d te laat" / "My tasks: %1$d open, %2$d of them overdue")

- [ ] **Step 4: Run to see them pass**

Run: `swift test --package-path Packages/BrievieKit --filter "DocumentsMyTasksTests|DocumentsScopeTests|DocumentsTodoListTests|EnglishCatalogTests|CatalogKeyCoverageTests"`, then `make test`, `make lint`, `make build`.
Expected: PASS; the existing scope and inbox suites are unchanged.

- [ ] **Step 5: Commit**

```bash
git add Packages/BrievieKit App/RootView.swift
git commit -m "feat(tasks): Mijn taken in the title menu, with its count and a link from the Inbox"
```

---

### Task 8: Reminders and calendar follow "Mijn taken"

**Files:**
- Modify: `K/Sources/BrievieCore/Documents/WorkspaceDocuments.swift` (`phoneTasks`)
- Modify: `K/Sources/BrievieCore/Calendar/CalendarSettings.swift` (protocol and every conformer in the file)
- Modify: `App/AppEnvironment.swift` (`AppCalendar`), `App/BrievieApp.swift` (the reminders' source)
- Modify: `K/Sources/FeatureWorkspace/CalendarSettingModel.swift`, `SettingsView.swift`, `WorkspaceStrings.swift`, `Resources/Localizable.xcstrings`
- Test: `K/Tests/BrievieCoreTests/PhoneTasksTests.swift` (new), `K/Tests/BrievieCoreTests/CalendarSettingsTests.swift`, `K/Tests/FeatureWorkspaceTests/CalendarTaskPartTests.swift` (new)

**Interfaces:**
- Consumes: `WorkspaceDocuments.myTasks`, `.openTasks` (Task 2).
- Produces:
  - `WorkspaceDocuments.phoneTasks(_ part: MyTasksPart) async throws(DocumentsError) -> [WorkspaceTask]` — `myTasks(part: part, status: .open).items`; on `.notSupported` → `openTasks()`. `part` is only `.mine` or `.all` (a precondition-free `switch`: `.toPickUp` is treated as `.mine`).
  - `CalendarSettings.taskPart(for workspace: UUID) -> MyTasksPart` (default `.mine`) and `setTaskPart(_ part: MyTasksPart, for workspace: UUID)`; stored next to `showsDetails`, forgotten with the pairing like the switches.
  - `CalendarSettingModel.taskPart: MyTasksPart` and `setTaskPart(_:)` — stores, then syncs once if the switch is on (the `setShowsDetails` pattern).
  - App: reminders' `TaskSource` = `phoneTasks(.mine)`; calendar's `TaskSource` = `phoneTasks(settings.taskPart(for: workspace))`.

- [ ] **Step 1: Write the failing tests**

`PhoneTasksTests`:
- `remindersReadMine` — `phoneTasks(.mine)` records `.myTasks(url, .mine, .open)` and returns its items.
- `phoneTasksFallBackToListTasksOn404` — `myTasks` throws `.other("http_404")` → records `.openTasks` and returns those tasks.
- `aRealErrorIsNotAFallback` — `myTasks` throws `.unreachable` → throws `.unreachable`, no `.openTasks` call (a failed read must not swap in the whole workspace).
- `toPickUpIsNeverReminded` — `phoneTasks(.toPickUp)` asks `.mine`.

`CalendarSettingsTests`: `taskPartDefaultsToMineAndIsStoredPerWorkspace`, `taskPartIsForgottenWithThePairing`
(whatever the existing "forget" path is for `showsDetails`).

`CalendarTaskPartTests`: `switchingToAllTasksSyncsOnce` (switch on → one extra `sync(workspace:)`),
`switchingWhileOffOnlyStores`.

- [ ] **Step 2: Run to see them fail**

Run: `swift test --package-path Packages/BrievieKit --filter "PhoneTasksTests|CalendarSettingsTests|CalendarTaskPartTests"`
Expected: compile errors.

- [ ] **Step 3: Implement, the App wiring, and the setting's texts**

In `SettingsView`, under "Toon de omschrijving in de agenda", a `Picker` "Welke taken" / "Which tasks" with
"Mijn taken" / "My tasks" (default) and "Alle taken" / "All tasks", footer "Mijn taken: alleen taken die bij
jou horen. Alle taken: elke taak die je mag zien." / "My tasks: only tasks that are yours. All tasks: every
task you may see.". Shown only while the switch is on. The planner already deletes events of tasks that no
longer come back, so switching to "Mijn taken" clears the others; nothing to add there.

- [ ] **Step 4: Run to see them pass**

Run: the filter of Step 2, then `make test`, `make lint`, `make build`.
Expected: PASS; `CalendarSyncTests`, `DeadlineRemindersTests` unchanged.

- [ ] **Step 5: Commit**

```bash
git add Packages/BrievieKit App
git commit -m "feat(tasks): reminders and the calendar follow Mijn taken, with an all-tasks choice"
```

---

### Task 9: An amount on a payment task in the review

**Files:**
- Modify: `K/Sources/BrievieCore/Documents/DocumentModels.swift` (`TaskDraft.amount: String = ""`)
- Modify: `K/Sources/BrievieCore/Server/LiveBrievieServer+Documents.swift` (confirm body: `TaskIn.amount`)
- Modify: `K/Sources/FeatureDocuments/ReviewDraft.swift` (prefill), `ReviewView.swift` (the field), `ReviewModel+Tasks.swift` (`setAmount`), `DocumentStrings+Tasks.swift`, `Resources/Localizable.xcstrings`
- Test: `K/Tests/BrievieCoreTests/LiveBrievieServerDocumentsTests.swift`, `K/Tests/FeatureDocumentsTests/ReviewTaskEditTests.swift`

**Interfaces:**
- Consumes: `TaskAmount` (Task 1).
- Produces: `TaskDraft.amount: String` (as typed, empty = unknown); `ReviewModel.setAmount(_ text: String, for taskID: UUID)`; `ReviewModel.amountIsValid(for taskID: UUID) -> Bool`.

Rules: the field shows only on a `pay` task ("Bedrag" / "Amount", `.decimalPad`, placeholder "€ 0,00"). The
draft is prefilled from the proposal `invoice_amount_incl` (group 0) when the review adds or finds the pay
task, marked unchecked like the other AI values (`markUnchecked`), its quote shown as the other quotes are.
On confirm: `TaskAmount.parse(input:locale:)` → `TaskAmount.api` → `TaskIn.amount`; empty or unreadable →
`""`. An unreadable non-empty text blocks "Bevestigen" with "Dit bedrag kan Brievie niet lezen. Schrijf het
als 1234,56." / "Brievie cannot read this amount. Write it as 1234.56." (the confirm-blocking pattern the
review already uses for its other checks).

- [ ] **Step 1: Write the failing tests**
  - `LiveBrievieServerDocumentsTests.confirmSendsTheAmountAsADecimalString` — a draft with `amount: "1.234,56"` on a Dutch locale → captured body has `"amount":"1234.56"`; empty → `"amount":""`.
  - `ReviewTaskEditTests.payTaskIsPrefilledFromTheInvoiceAmount` — proposal `invoice_amount_incl` = `"1234.56"` → the pay task's `amount` is that value, shown in the user's notation, unchecked.
  - `ReviewTaskEditTests.unreadableAmountBlocksConfirm` — `setAmount("twaalf", …)` → `amountIsValid == false` and confirm is not sent.
  - `ReviewTaskEditTests.amountFieldOnlyOnPayTasks` — a `respond` task has no amount in the sent review.
- [ ] **Step 2: Run to see them fail** — `swift test --package-path Packages/BrievieKit --filter "LiveBrievieServerDocumentsTests|ReviewTaskEditTests"` → compile errors.
- [ ] **Step 3: Implement** (as above; texts in `DocumentStrings+Tasks.swift`).
- [ ] **Step 4: Run to see them pass** — the same filter, then `make test`, `make lint`. Expected: PASS.
- [ ] **Step 5: Commit**

```bash
git add Packages/BrievieKit
git commit -m "feat(review): an amount on a payment task, prefilled from the invoice"
```

---

### Task 10: The letter's task rows: amount, who has it, Ik doe dit

**Files:**
- Modify: `K/Sources/BrievieCore/Documents/DocumentModels.swift` (`ConfirmedTask`), `K/Sources/BrievieCore/Server/LiveBrievieServer+Documents.swift` (decode `TaskOut.amount`, `term_quote`, `assigned_to_id`, `assigned_to_name`)
- Modify: `K/Sources/FeatureDocuments/ConfirmedDocumentModel.swift`, `ConfirmedDocumentSections.swift`
- Test: `K/Tests/BrievieCoreTests/LiveBrievieServerDocumentsTests.swift`, `K/Tests/FeatureDocumentsTests/ConfirmedDocumentModelTests.swift`

**Interfaces:**
- Consumes: `TaskAmount`, `TaskWords.amount` (pattern), `WorkspaceDocuments.assignTask`, `.currentUserID` (Task 2).
- Produces: `ConfirmedTask` gains `amount: Decimal? = nil`, `termQuote: String = ""`, `assignedToID: UUID? = nil`, `assignedToName: String = ""`; `ConfirmedDocumentModel.takeOn(_ taskID: UUID) async`, `release(_ taskID: UUID) async`, `isMine(_ task: ConfirmedTask) -> Bool` (after `currentUserID()` was read once on load; false until then).

Scope note: `DocumentOut.tasks` is `TaskOut`, which has no `reason`, `for_names`, `can_edit` or
`needs_deadline`. The letter therefore shows the amount, "Bij Anne" when someone else has it, "Jij doet dit"
when it is mine, and the buttons "Ik doe dit" (nobody has it) / "Niet meer aan mij" (mine) for an editor — not
"Voor jou / Voor Piet". "Geef aan…" and "Datum invullen" stay in Mijn taken.

- [ ] **Step 1: Write the failing tests**
  - `LiveBrievieServerDocumentsTests.detailDecodesTheTaskAmountAndAssignee`.
  - `ConfirmedDocumentModelTests.takeOnAssignsToMeAndUpdatesTheRow` — records `.assignTask(url, task, me)`, the row says "Jij doet dit", `onTasksChanged` called.
  - `ConfirmedDocumentModelTests.aViewerCannotTakeOn` — `canEdit: false` → no call.
- [ ] **Step 2: Run to see them fail** — `swift test --package-path Packages/BrievieKit --filter "LiveBrievieServerDocumentsTests|ConfirmedDocumentModelTests"`.
- [ ] **Step 3: Implement** — `ConfirmedTaskRow` gains the amount after the type/deadline line and the "Bij Anne" / "Jij doet dit" line; the buttons are borderless footnote buttons and `accessibilityActions` of `TaskTickRow`.
- [ ] **Step 4: Run to see them pass** — the same filter, then `make test`, `make lint`. Expected: PASS.
- [ ] **Step 5: Commit**

```bash
git add Packages/BrievieKit
git commit -m "feat(documents): a letter's tasks show the amount and who does them"
```

---

### Task 11: The own-phone sentence on the pairing screen

**Files:**
- Modify: `K/Sources/FeaturePairing/PairingStrings.swift`, `PairingView.swift`, `Resources/Localizable.xcstrings`
- Test: `K/Tests/FeaturePairingTests/PairingModelTests.swift` (or the suite that checks the pairing texts) — `ownPhoneSentenceHasADutchValue` through `CatalogParity`.

Text (spec S 9): "Koppel alleen je eigen telefoon. Wie een andere telefoon gebruikt, koppelt die met een eigen
account." / "Only pair your own phone. Someone who uses another phone pairs it with their own account." Shown
as a footnote under the scan button of the first pairing screen.

- [ ] **Step 1: Write the failing test** — run `swift test --package-path Packages/BrievieKit --filter FeaturePairingTests` → FAIL (key missing).
- [ ] **Step 2: Add the key, the view line, the English** — run the same filter and `EnglishCatalogTests` → PASS; `make lint`.
- [ ] **Step 3: Commit**

```bash
git add Packages/BrievieKit/Sources/FeaturePairing Packages/BrievieKit/Tests/FeaturePairingTests
git commit -m "feat(pairing): say that each person pairs their own phone"
```

---

### Task 12: Check it on the simulator

**Files:** none (a fix found here goes into the task that owns it, with its test).

- [ ] **Step 1: Everything green** — `make test`, `make lint`, `make check-project`, `make build`. Expected: all pass, `git status` clean apart from intended changes.
- [ ] **Step 2: Run against a host on `main`** (the developer's own local host; do not start or touch any Docker project or the test server `brievie` for this — ask the owner which server to pair with). Build and launch on the iPhone 17 simulator (newest iOS runtime) with the iOS Simulator tool, pair, and check, with screenshots:
  1. The app opens on the Inbox; the title menu shows "Mijn taken · N open…" above "Inbox"; the Inbox shows the "Mijn taken: …" row, orange with "te laat" when something is late.
  2. "Mijn taken": groups in order with counts, a late row in orange **and** words, amount "€ 1.234,56", "Van … · Voor jou", "Uit de brief: '…'", a "Datum nodig" row with "Datum invullen".
  3. Tick → struck through with "Ongedaan maken"; undo; tick again, pull to refresh → under "Afgerond" with "Afgevinkt door … op …"; "Toch niet klaar" brings it back.
  4. A business workspace: "Op te pakken" with "Ik doe dit"; after it the task is in the own list. "Geef aan…" lists only readers.
  5. "Datum invullen" with a date before the letter → the sentence; a valid date moves the row.
  6. Airplane mode: pull to refresh keeps the list and shows the unreachable message; a tick flips back with "Dat lukte niet…".
  7. VoiceOver on: a row reads "Klaar: …" as the tick and offers the actions in the rotor; group headers are headers.
  8. Settings → Accessibility → Larger Text at maximum: rows wrap, nothing clipped. Dark mode.
  9. English (Settings → Language → English): "My tasks", "To pick up", "Done", "I'll do it"; no Dutch left.
  10. Settings in the app: the calendar switch on, "Welke taken: Alle taken" → events of others' tasks appear; back to "Mijn taken" → they leave.
- [ ] **Step 3: Report** what was checked, with the screenshots, in the PR description.

---

## Not in this plan

- The letter-status badge (Nieuw / Openstaand / Afgehandeld, "wacht op reactie", "uitgesteld"): its own
  design; it fills `MyTaskRowView`'s badge slot and a status line on the letter.
- Opening the app on "Mijn taken" (spec Q1): the owner keeps the Inbox as the start screen.
- History events `task_assigned`, `task_unassigned`, `task_deadline_set` and origin `system`: the app shows no
  letter history, so nothing to do; when it does, it skips unknown kinds.
- Tasks made by hand, a team overview, push on hand-over, digests (spec S 3, S 10: later, server first).

## Self-review notes

- Spec S 14 coverage: API sync and decode → Tasks 1–2; screen → Tasks 3–7; reminders and calendar → Task 8;
  review amount → Task 9; letter detail → Task 10; pairing sentence → Task 11.
- Server facts this plan builds around: `TaskOut` (letter detail) lacks `reason`, `for_names`, `can_edit`,
  `needs_deadline` (Task 10 is scoped down); the pairing knows the user's name but not their id, so "Ik doe
  dit" reads `getMe` once; `TaskItemOut` has no letter date, so a date before the letter is caught by the
  server's 422; the API version stayed `1.0.0`, so new endpoints are found by their 404.
