# English glossary

The app speaks Dutch and English; it follows the iPhone's language. The Dutch text is the source
(`developmentLanguage: nl`); this list fixes the English words so every screen uses the same one.
English is plain and friendly, in sentence case, and reads fine for British and American readers.
The host's `docs/GLOSSARY.md` (section "English in the interface") is the shared source; this list holds the
same terms the app uses plus the app-only ones. When they differ, the host's glossary wins.

| Dutch | English | Note |
|---|---|---|
| post (all letters together) | mail | "All mail", "Add mail", "Search your mail". One choice everywhere: not "post". |
| brief | letter | A single item. "Scan a letter", "Letter date". |
| Alle post | All mail | Scope of the list. |
| Inbox | Inbox | Scope of the list; the same name as the web. |
| termijn | deadline | Never "term" or "due date". "Deadline" is also the field of a task. |
| taak / taken | task / tasks | |
| werkruimte | workspace | |
| koppelen / ontkoppelen | pair / unpair | "Pairing code" for koppelcode, "pairing details" for koppelgegevens. |
| apparaat, toestel, telefoon | device (server side), phone (on this phone) | "Devices" is the server's list. |
| meekijker / Kijker | viewer | Role badge "Viewer"; "view-only access" in a sentence. |
| Lid | member | |
| Beheerder | admin | |
| herstelblad | recovery sheet | Not in the app yet. |
| autopilot | autopilot | Not in the app yet. |
| afzender | sender | |
| geadresseerde / Op naam van | addressee / addressed to | "Addressed to Papa". |
| voorstel | suggestion | Of the AI or a rule; verb "dismiss" for negeren, "add" for toevoegen. |
| Controleren | Check | Status and title of the review; "Check this carefully". |
| Bezig… | Processing… | A letter the server is reading. |
| Bevestigen | Confirm | |
| agenda | calendar | "Put deadlines in my calendar". |
| meldingen | notifications | "Deadline notifications". |
| toegangsscherm | Lock Screen | Apple's name, capitalised. |
| toegangscode | passcode | |
| scan | scan | Verb and noun. "Rotate" for draaien. |
| BSN | BSN (citizen service number) | Explained once, in the search notice. |
| Taak: betalen, reageren, bezwaar maken, aanvragen, keuring, opzeggen, verlengen, aangifte | Pay, Respond, File an objection, Apply, Inspection, Cancel contract, Renew, File a return | "Object" and "Cancel" alone read as a noun and a button. |
| Soort: factuur, aanslag, beschikking, rekening, herinnering, aanmaning, polis, jaaropgave, loonstrook, bonnetje | Invoice, Tax assessment, Decision, Bill, Reminder, Payment demand, Policy, Annual statement, Payslip, Receipt | |
| persoon | person | "Choose persons"; never "people" for the list of persons. |
| App koppelen (page on the web) | Pair the app | As an action in a sentence; the web page itself is called Devices. |
| Mijn taken | My tasks | The member's own list of tasks; the menu entry and the screen. |
| Op te pakken | To pick up | Tasks nobody has taken yet (an organisation only). |
| Alle taken | All tasks | Every task the member may see. |
| Afgerond, Afgevinkt door | Done, Ticked off by | "Toch niet klaar": "Not done after all". |
| Datum nodig, Datum invullen | Needs a date, Set a date | The letter names a term but no date. |
| Ik doe dit | I'll do it | Taking a task nobody has yet. |
| Geef aan…, Niet meer aan mij | Hand over…, Not mine any more | |
| Te laat, Binnen 7 dagen | Overdue, Within 7 days | Never "this week". |
| Mijn post | My post | The member's own letters and the start screen; the one place where "post" stays "post" (host decision B1). |
| Ongelezen; Markeer als gelezen / ongelezen; Alles gelezen; Alleen ongelezen | Unread; Mark as read / Mark as unread; Mark all read; Unread only | Per member. Swipe actions: "Read" / "Unread". |
| Blijft liggen; In de Inbox te lang; Nog niet geopend | Lying too long; Too long in the Inbox; Not opened yet | "Ligt er 4 dagen": "Waiting 4 days". |
| Taken (tab), Meer | Tasks, More | The tab bar; the task screen itself is "My tasks". |
| Instellingen | Settings | |
| Voor wie; Iedereen | For whom; Everyone | The filter of All mail. |
| Werkruimte kiezen | Choose workspace | The pill's sheet. VoiceOver: "Workspace: Thuis. Choose another workspace". |
| Scannen, Zoeken, Naam kiezen | Scan, Search, Choose a name | Round quick actions. |

## Rules

- Dates, amounts, lists and relative deadlines are formatted by the system in the user's locale. Never fix a
  `nl_NL` locale in code; the letter's own text stays as it is.
- Every key in every String Catalog needs an `en` value with the same placeholders (`%@`, `%d`, `%lld`,
  `%1$@`) as `nl`. `EnglishCatalogTests` fails CI when one is missing or differs.
- Plural keys carry `one` and `other` in both languages.
- Time of day in a sentence is written "9 am", not "9:00".
