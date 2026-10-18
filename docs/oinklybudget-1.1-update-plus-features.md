# OinklyBudget 1.1: update plus features

Drafted 2026-10-16. Nothing here is started. Version 1.0 is in App Review and does not change.

## Goal

Make the Mac app more useful for people who keep their books on paper and PDF, and for households that share one Mac. 1.1 adds export to PDF and CSV for every account and the Transactions page (to print, open the PDF), widgets that show upcoming bills and reminders (no financial details), a few more reports, some everyday bookkeeping features, and a shared data file that two users on one Mac can use (one at a time), controlled from Settings ▸ Data. The direction stays the same: a full desktop program, no bank linking, no accounts, no network.

## What is already there

Registers, transfers, bills and bill pay, budgets, goals, investments and liabilities, reports and top spending, reconcile, search, receipts, custom reminders, CSV import and export, `.pig` backup and restore, Help, release notes. There is no printing and no PDF output yet.

## Must have: export to PDF and CSV

Direction: instead of building a full printing system (print panel, page setup, ⌘P on every window), 1.1 **exports to PDF and CSV**. To print, the person opens the PDF and prints it from Preview. That is far less work, behaves the same on every Mac, and gives people a file they can keep or email.

| Where | What it does |
|---|---|
| **Every account: Export to PDF** | An account's transactions for a range the person picks (month, year, all, or custom dates), with a running balance, as a PDF statement. |
| **Every account: Export to CSV** | The same transactions and range as a spreadsheet file, in the layout the CSV import reads, so it round-trips. |
| **Main Transactions page: Export to PDF** | All accounts together, with a **month selector** (pick a month, or a month range) and an option to limit to one account or category. Also a CSV option. |
| **Single transaction** | Export one transaction with its details and receipt to PDF (from the transaction detail window). |
| **Reports, budget, bills, net worth** | Use the same exporter to give each an Export to PDF button. Lower priority than the account and Transactions exports; do them after those if time allows. |

Not planned: a Print command, ⌘P, page setup, and a print preview. A PDF opened in Preview already has those. This replaces the earlier plan for printing across the app.

How to build it:

- Make each exportable thing a SwiftUI "report page" view that takes its data and a paper size (US Letter or A4, from the system region, with a choice in the export sheet).
- Render pages with `ImageRenderer` into a PDF, with page breaks for long lists and a repeating header row on each page. Add a footer with the title, date range and page numbers.
- One shared **Export sheet** for all of it: what to export, the range or month, paper size, then a Save panel. After saving, offer "Show in Finder" and "Open in Preview".
- A shared set of export styles (fonts, colours that print well in black and white, table lines).
- CSV export uses the existing `TransactionCSV` writer, filtered by account and date range.
- Test with long registers (thousands of rows) for speed and page breaks, and with receipts that are images and PDFs.
- If encryption is on, exports are plain files the person chose to make. Say so in the export sheet.

### Effort

About 1.5 to 2 weeks part-time: shared exporter and sheet (3 days), account PDF and CSV (3 days), Transactions page with month selector (2 days), single transaction and the other screens (3 to 4 days), tests and Help.

## Must have: CSV import that handles any bank file

Direction: plain CSV is the one import format, and it should handle whatever a bank gives you. No bank linking, no other programs' formats (see "Not planned" below). The same importer is used from two places.

### What is there now

Import Transactions (CSV) lives only in Settings ▸ Import & Export (`ImportExportSettingsView`, `TransactionCSV.swift`). It guesses columns from header names (Date, Payee/Description, Amount or Debit/Credit, and so on), asks which account loose rows belong to, and can skip duplicates. It fails with an error when the header names are not ones it knows, and there is no preview.

### What to add

| Feature | Notes |
|---|---|
| **Import Statement… on every account** | A button in each account's register or account menu (and File menu) that imports a CSV straight into that account. Every row goes to that account, with no account question. Rows for other accounts are never touched. |
| **Preview before importing** | A table of the first rows as they will be read, with counts: new, duplicates skipped, problems. Nothing is saved until the person clicks Import. |
| **Column mapping** | If the headers are not recognised (or the guess is wrong), a screen lets the person pick which column is Date, Payee, Amount (or Debit and Credit), Memo and Category. Unused columns can be ignored. |
| **Remembered per bank** | Save a mapping with a name ("Chase checking") and reuse it. It is picked automatically when a file's headers match. |
| **Date formats** | Month/day/year, day/month/year, year-month-day, two-digit years, with dates shown in the preview so the person can see which is right. |
| **Amount formats** | Separate debit and credit columns, one signed column, and a "credit card" setting where a positive number means a charge. Handle currency symbols, thousands separators, commas as decimals and amounts in parentheses. |
| **Files with extra lines** | Skip title lines above the header and summary lines below the data, which many banks add. Choose the delimiter (comma, semicolon, tab) and text encoding. |
| **Duplicate handling** | Keep skipping matches (same day, account, payee and amount), but show them in the preview and let the person override. Also warn when the dates overlap an earlier import. |
| **Undo an import** | One click to remove everything the last import added, in case the mapping was wrong. |
| **Payee clean-up on import** | Use the payee memory the register already has to fill categories, and tidy bank text such as card numbers and store codes. |

### Notes

- Everything is built from plain parsing in the app, with no third-party code. Keep `TransactionCSV` as the one reader and put the mapping and preview on top of it.
- Test with real files from several banks and card issuers, large files (tens of thousands of rows), odd encodings, and quoted fields with commas and line breaks.
- Only CSV (and text files with the same layout). PDF statements are not parsed.
- Needs no model change, except possibly a small stored "import" tag on each transaction so Undo can find what an import added. If that is wanted, it goes in with the other schema changes.
- Help gets a page on importing a statement, with a step-by-step example.

### Effort

About 1.5 to 2 weeks part-time: reader and format options (3 days), preview and mapping screens (4 days), saved mappings, Undo and duplicate overlap warning (3 days), the per-account button, tests with real files and Help (2 to 3 days).

## Should have: reports and everyday features

Pick from this list; each one is small to medium.

- **More reports:** income and expense by category and by payee, monthly cash flow, net worth over time, year-end summary, tax-related category summary.
- **Report options:** date range presets, account and category filters, compare to last period, export the table as CSV.
- **Memorised and recurring transactions:** the register already learns payees; add scheduled repeats (paycheque, rent) with a reminder or auto-entry.
- **Split transactions:** one payment split across several categories.
- **Tags or labels** on transactions, usable in reports.
- **Find and replace** across payees and categories, plus a clean-up of duplicate payees.
- **Check printing layout** (optional): print checks on standard check stock.

**Not planned: Quicken and other program formats.** No QIF, OFX or QFX import, and no importing from Quicken or any other finance program's files. Those formats are tied to other companies' software, so the app stays with plain CSV files (see "Must have: CSV import" above). Bank statements that come as PDFs can be kept as attachments (see below) but are not read or parsed.

## Nice to have

- Attachments beyond receipts (PDF statements kept with an account).
- Keyboard shortcuts review and more menu commands.
- Accessibility pass (VoiceOver, larger text) for the new screens.
- Settings for default report period, paper size and export style.

## Shared data file: two users on one Mac (MOVED OUT OF 1.1, see the 1.2 plan)

> **Update 2026-10-18:** this is no longer part of 1.1. A working prototype is saved on the `shared-data-prototype` branch. The text below is kept as the design record. Everything else in this plan that says it depends on the shared file (the encrypted data file) needs a rethink; see the README.

Goal: two people on the same Mac can use the same OinklyBudget data file, **one at a time**. No sync, no cloud, no accounts inside the app. (Both editing at the same moment is a much harder problem and is not part of this. If you want that, say so, because it changes the design.)

### What it does

- The data is a file the household chooses the location of (Documents, or `/Users/Shared` when each person has their own Mac login). Double-clicking it in Finder also opens it.
- **All of it lives in Settings ▸ Data**, not in the File menu. The File menu gets nothing new for this. The Data tab (it already holds data tools) gets a "Data File" section:
  - **Current file:** the file name and full path, with Show in Finder.
  - **Who has it open:** the person's name and since when, and the last save.
  - **Buttons:** Choose a Different File…, Create a New Data File…, Move This File…, Open Recent (a pop-up list), and "Close File So Someone Else Can Use It".
  - **Read-only status** shown when the file was opened read-only.
  - **Backup:** the existing backup options stay in the same tab.
  - The file name still shows in the window title.
- **Opens the last file at launch.** If the file is missing, a clear screen says so and offers Locate, Open Another, or New. It never starts an empty database silently.
- **One person at a time.** Opening a file leaves a small lock beside it with who has it and since when. A second person sees "Sam has this file open since 3:10 PM" and can open it read-only, open another file, or cancel.
- **Stale locks** after a crash: if the lock is old and the app that wrote it is gone, offer "Take Over" with a warning.
- **Existing 1.0 data is copied, not moved.** The first launch of 1.1 copies the data to a file the person picks, checks the counts match, keeps the original untouched, and offers a `.pig` backup first.

### The main risk, and the answer

Decided: each person has their own Mac login, so the file lives in a shared place such as `/Users/Shared`, and two logins can be signed in at once through fast user switching. Two logins sharing one live database is risky: SQLite creates side files while running, and files made by one login can be unwritable by the other. So the design is **check out and check in**, not opening the shared file live:

- Opening takes the lock and copies the shared file to a private working copy in the app's own storage; editing happens on the copy.
- Saving and closing writes the copy back to the shared file in one safe replace step, then releases the lock. The shared file is only ever a finished, closed file.
- Autosave writes back on a timer and when the app is hidden. After a crash, the app offers to recover the unsaved working copy.
- The app sets permissions on the shared file and its folder so every login can read and write it, and checks this on open with a clear message if it can't.

### Technical notes

- The app is sandboxed with user-selected file access already on. A stored bookmark of the last file is needed; bookmarks are per Mac login, so each person opens the shared file once with the Open dialog.
- The lock file records the Mac user name, the time, and a "still in use" timestamp refreshed every minute. A different login cannot check whether the first login's app is still running, so a lock is treated as stale only when its timestamp has stopped updating, and Take Over always asks first.
- With fast user switching, both people can be signed in with the app open. The second person sees who has the file and can wait, so "Close File So Someone Else Can Use It" must be easy to find.
- Older files open and are upgraded; newer files are refused with a clear message.
- The file path is shown in Settings ▸ Data, since "where is my file?" will be the common question.
- This is the riskiest work in 1.1 because it touches how data is saved. Back up first, test crashes (kill the app mid-edit, stale locks), and test with large data.

### Effort

About 4 to 5 weeks part-time: prototype (3 to 5 days), Settings ▸ Data section and bookmark (1 week), sharing and locks (1 week), safety and recovery (1 week), migration (3 to 5 days), Help and release (3 to 5 days).

## Fixes from complaints

Things people (and the owner) have complained about. They are small, so they go in 1.1 ahead of the new features.

| Complaint | What to do |
|---|---|
| **Edit Transaction has no way to add a receipt.** Receipts can be attached when a transaction is created, but the Edit Transaction sheet (`EditTransactionSheet` in `RegisterView.swift`) does not show the receipt picker. | Add the same receipt picker the New Transaction, Bill Pay, Cash and Credit Card windows use (`ReceiptPicker`), so a receipt can be added, replaced, removed, or marked "no receipt" when editing. Show the current receipt with a preview. Test with image and PDF receipts, and with a transaction that already has one. |
| **The side panel can be dragged to different widths, and people are starting to complain about it.** | Make the side panel one fixed width every time the app opens, with no dragging. In `MacRootView.swift` the panel uses `navigationSplitViewColumnWidth(300)`, which sets a starting width but still lets it be resized; use the same minimum, ideal and maximum width instead, and check that the window-size memory does not restore an old width. Check long account names still fit, and that the panel still shows when the window is small. |
| **Pages look unfinished at the bottom: long lists seem to run off the floor, and the app name isn't centered.** | Add a small status bar along the bottom of every page, like older desktop programs: what you are looking at on the left (for example "12 transactions · October 2026 · Checking") and a quick Help link on the right. It gives every page a floor, so lists scroll inside their own area above it. Centre the app name in the top bar so the top and bottom match. Report pages scroll inside the same set area. Built in `StatusBar.swift`; pages set their text with `.statusBarText(…)`. |

Also check these when the fixes are done: the new export sheets must not bring the bar back, and Help screenshots for the Edit Transaction sheet and the pages need retaking.

## Encrypted data file

Complaint: the information database is not encrypted. Anyone who can open the data file (a shared Mac login, a copied backup, a stolen laptop without FileVault) can read it.

**Can it be done without third-party code? Yes, with a catch.** The app stores data with SwiftData on SQLite, and neither encrypts the database file itself. The usual fix for that, SQLCipher, is third-party and is not wanted here. But Apple's own CryptoKit (AES-256-GCM) and the system Keychain are built in and need no outside code. The catch is that the live database can't be encrypted in place, so the file is encrypted **at rest**: sealed whenever it is closed, opened up only while the app is using it.

### What it does

- A new **Encrypt data file** option in Settings ▸ Data, with a passphrase the person chooses. Turning it on seals the file; turning it off asks for the passphrase first.
- **The shared file is only ever stored encrypted.** This fits the check-out and check-in design already planned for the shared data file: on check-out the app asks for the passphrase (or reads it from that login's Keychain if the person chose "Remember on this Mac"), decrypts into the private working copy, and on check-in seals it again and replaces the shared file in one step. Nobody reading `/Users/Shared` sees anything but ciphertext.
- **`.pig` backups** are encrypted with the same passphrase, so an exported backup is not readable either. Old unencrypted backups still restore.
- The lock file, the file name and the "who has it open" text are not secret and stay readable; they hold no financial data.
- Widgets: the widget snapshot holds only bill names, reminder titles and dates, with no amounts or account details, so it is not encrypted and is not affected.

### Technical notes

- Passphrase to key with PBKDF2 (CommonCrypto, part of macOS) using a random salt and a high iteration count, then CryptoKit `AES.GCM` to seal. The file stores a small header: format version, salt, iteration count, nonce. Never store the key or the passphrase in the file.
- "Remember on this Mac" stores the derived key in the Keychain for that login only. Keychains are per login, so the second person enters the passphrase once on their own login, like the file bookmark.
- Large files: encrypt and decrypt in chunks so a big database doesn't use a lot of memory, and test speed on a multi-year register.
- Writes go to a temporary file and are verified (decrypt and check) before the replace, so a failed encryption can't destroy the data.
- Honest limit: **while the file is open, the working copy sits unencrypted** in the app's private storage. It is deleted on close, covered by FileVault if the Mac has it, and recovered or wiped after a crash. This protects the file at rest and in sharing, not a Mac that is unlocked and in use. Say so in Help instead of overselling it.
- **No passphrase recovery.** There are no accounts and no server, so a forgotten passphrase means the file cannot be opened. The setup screen must say this plainly and offer to save a recovery key (a long random code to print or store somewhere safe).
- Older unencrypted files open as before; encryption is opt-in, so existing users are not locked out by an update.

### App Store note

The Info plist currently says the app uses no non-exempt encryption (`ITSAppUsesNonExemptEncryption` is `false`). Encrypting the user's own data with standard algorithms changes the export compliance answers. Re-answer the questions in App Store Connect for this build, and check whether a yearly report is needed, before uploading.

### Effort

About 1 to 1.5 weeks part-time: key handling and the file format (3 days), Settings ▸ Data options, recovery key and Keychain (3 days), encrypted `.pig` backups, crash tests and large-file speed (2 to 3 days). It shares code with the shared data file work, so it is built right after it.

## Widgets

Goal: a few small macOS widgets (Notification Center and desktop) that give a brief summary of what is coming up, with **no financial information at all**: no amounts, no balances, no account names or numbers. Only what is due and when. No network and no account. Clicking a widget opens the app to the matching screen.

### What it does

| Widget | Sizes | Shows |
|---|---|---|
| **Upcoming bills** | Small, medium | The next bills due by name and date ("Electric, in 3 days"), with overdue ones marked. No amounts. |
| **Reminders and events** | Small, medium | The next custom reminders and calendar-style events from the app (the app already has custom reminders), by title and date. |

- Widgets are read-only. They never change data.
- Because nothing on them is financial, there is no "hide amounts" setting and no balances, budget or spending widgets.
- Keep titles generic: a bill is shown by its name only, and the person controls those names.

### How it fits with the data file

- A widget runs in its own sandboxed process and must not open the live database. Opening the database from two processes is the same SQLite problem the shared data file design avoids.
- So the app writes a small **snapshot** (bill names and due dates, reminder titles and dates, a timestamp, and nothing else) as JSON into an App Group container whenever data changes and when the app is hidden or quit. Widgets only read the snapshot, and the app asks WidgetKit to reload timelines after each write.
- The snapshot holds no amounts or account details, so it does not need to be encrypted and the encrypted data file does not affect it.
- The snapshot belongs to the Mac login that has the file checked out. With the shared data file, each login keeps its own App Group container, so one person's widgets never show the other's open file. When the file is closed, widgets show the last snapshot with "Updated <time>", or "Open OinklyBudget to refresh" if there is none.
- The snapshot is derived data: it can be deleted and rebuilt at any time, and it is not part of `.pig` backups.

### Technical notes

- Add a WidgetKit extension target, an App Group entitlement on the app and the extension, and a small shared Swift module for the snapshot types (no SwiftData in the extension).
- Use `widgetURL` deep links into Bills and Reminders. A small App Intent can let the person choose what a widget shows.
- "Due in 3 days" must stay correct without the app running: give WidgetKit a timeline with entries at midnight and at each due date.
- Test dark mode and the tinted widget style.
- Needs the App Groups capability, and an App Review note that widgets read local data only and show no financial data.

### Effort

About 1 week part-time: extension target, App Group setup and snapshot writer (3 days), the two widgets (2 days), testing with the shared file and Help (1 to 2 days). It follows the shared data file build, which settles how and when the app saves.

## Order of work

0. **Complaint fixes (2 to 4 days):** receipt picker on Edit Transaction, fixed side panel width, and the footer bar change. Small and visible, so they go first, in parallel with the prototype if needed.
1. **Shared data file prototype (3 to 5 days):** build check-out and check-in on a file in `/Users/Shared` and test it with two real Mac logins (including fast user switching): permissions, bookmarks per login, locks, crashes. This decides the design, and it is the riskiest work, so it goes first.
2. **Shared data file build:** Settings ▸ Data section, last-file bookmark, missing-file screen, locks with who and when, read-only open, take-over for stale locks, safe write-back and crash recovery, and the first-run copy of existing data.
3. **Encrypted data file:** passphrase and file format, Settings ▸ Data options, recovery key, encrypted `.pig` backups. Built on the shared file's check-out and check-in, so it comes straight after it.
4. **Export foundation:** shared report page and Export sheet, PDF and CSV export on every account, month selector on the Transactions page. Prove it on the register.
5. **Export everywhere else:** single transaction, budget, bills, reports, net worth.
6. **CSV import:** the reader and format options, preview and column mapping, saved mappings, undo, and the Import Statement button on every account. Test with real files from several banks.
7. **Widgets:** App Group and snapshot writer, then the two widgets (bills, reminders and events). After the shared file build so the snapshot follows the checked-out file.
8. **New reports** and report options.
9. **Everyday features:** pick two or three from "Should have" (recurring and splits are the strongest).
10. **Polish:** Help pages and screenshots for every new feature (including Settings ▸ Data and widgets), release notes, accessibility check.
11. **Release:** TestFlight, submission, website and listing update.

## Rough effort

| Part | Effort |
|---|---|
| Export to PDF and CSV (accounts, Transactions page, other screens) | 1.5 to 2 weeks |
| New reports and options | 1 to 2 weeks |
| Complaint fixes | 2 to 4 days |
| Encrypted data file | 1 to 1.5 weeks |
| CSV import and per-account import | 1.5 to 2 weeks |
| Widgets | about 1 week |
| Each everyday feature | 3 days to 2 weeks (splits and recurring are the larger ones) |
| Help, screenshots, release | 1 week |

About 4 to 7 weeks part-time for export, reports and two or three everyday features, plus about 4 to 5 weeks for the shared data file, plus about 1 week for widgets, plus 1 to 1.5 weeks for the encrypted data file, plus 1.5 to 2 weeks for CSV import, plus 2 to 4 days for the complaint fixes, so about 12 to 16 weeks in total. All of it is in 1.1. If the schedule slips, drop items from "Should have" first and keep export, the shared data file, encryption, CSV import and widgets.

## Release housekeeping

- Version 1.1, build number up by one for every upload. Keep the schema at `PiggybankSchemaV1` unless a feature needs a model change (splits, tags and recurring transactions do). If so, add `PiggybankSchemaV2` with a tested migration, and test with a copy of real data first.
- Backup before updating: remind users in the release notes.
- New screenshots for the listing and Help for the new features.
- Update the website product page and the "What's new" text.
- Remove the unused iCloud and push entitlements before the next upload, and add the App Group entitlement for widgets (the current entitlements file has none, and the project has no widget target yet).
- Widgets add a second target to the app: it needs its own bundle ID, provisioning and signing, and it ships inside the same Mac App Store submission.
- The shared data file changes how the app saves, so the release notes and Help explain it, and tell users to make a `.pig` backup before updating.
- New App Review notes: say the app still has no network access and the data file stays on the Mac.

## Risks

- **PDF quality:** long lists, page breaks and different paper sizes. Open the PDFs in Preview and print a few on a real printer.
- **Model changes** for splits, tags and recurring transactions need a migration. Keep them small and tested.
- **Scope:** export and the shared data file are the core of 1.1. Stop adding "Should have" features when the schedule slips.
- **Shared data file:** a damaged or unreadable file (two logins and SQLite side files), data loss during the first-run copy, lost edits if someone takes over a lock, stale locks after crashes, and "where is my file?" questions. Check out and check in, copy first and verify, back up first, and crash tests reduce these.
- **Encryption:** a forgotten passphrase means lost data, the working copy is unencrypted while the file is open, and a bug in sealing could damage a file. Recovery key, verify-before-replace, opt-in only, and crash and large-file tests reduce these.
- **CSV import:** a wrong guess about dates or signs can put bad data in an account, and every bank formats files differently. The preview, saved mappings, duplicate checks and Undo reduce this, and testing with real files from several banks.
- **Widgets:** stale dates (a widget showing a bill that was already paid) and mixing up two logins' data. The snapshot approach, a visible "Updated" time and per-login containers reduce these. Widgets show no financial data, so there is no privacy exposure from them.
- **Review:** the new version goes through App Review again. Keep release notes clear and the app free of crashes.

## Decisions needed

1. Which of the "Should have" features come in 1.1 (suggestion: recurring transactions and split transactions; CSV import is already a must have)?
2. Are check printing and attachments in or out?
3. Is any model change acceptable in 1.1, or should it be export and report features only?
3c. Footer bar: **decided.** A small status bar at the bottom of every page (page text on the left, Help link on the right) with the app name centred in the top bar. Still open: what else goes in it (for example a quick month switch or New Transaction button)?
3d. Encryption: in 1.1 (decided, from a complaint). Still open: is a recovery key required or optional, and is remember-on-this-Mac on by default? (Widget snapshots hold no financial data, so they are not part of this. The unencrypted working copy while the file is open is accepted.)
3e. CSV import: **in 1.1** (decided). Plain CSV only, with an Import Statement button on each account. Still open: is a stored "import" tag on transactions (for Undo) worth a small schema change?
3a. Widgets: **in 1.1** (decided). Two widgets, bills and reminders/events, with no amounts, account names or account numbers. Still open: should reminders and events also show events from the Mac's Calendar, or only the app's own reminders?
3b. Shared file: **decided.** One person at a time, across separate Mac logins. Both at once is not planned.
4. Release timing, after 1.0 is approved?
