# OinklyBudget 1.1: update plus features

Drafted 2026-10-16. Nothing here is started. Version 1.0 is in App Review and does not change.

## Goal

Make the Mac app more useful for people who keep their books on paper and PDF, and for households that share one Mac. 1.1 adds printing and PDF export across the app, a few more reports, some everyday Quicken-style features, and a shared data file that two users on one Mac can use (one at a time), controlled from Settings ▸ Data. The direction stays the same: a full desktop program, no bank linking, no accounts, no network.

## What is already there

Registers, transfers, bills and bill pay, budgets, goals, investments and liabilities, reports and top spending, reconcile, search, receipts, custom reminders, CSV import and export, `.pig` backup and restore, Help, release notes. There is no printing and no PDF output yet.

## Must have: printing and PDF

| Feature | Notes |
|---|---|
| **Print a register** | An account's transactions for a date range, with running balance. Print or Save as PDF. |
| **Print a transaction** | One transaction with its details and receipt. |
| **Print reports** | Every report and the spending charts: Print and Save as PDF from the report window. |
| **Print the budget** | Budget versus actual for a month or year. |
| **Print bills** | Upcoming and paid bills, as a list or a calendar. |
| **Net worth and account summary** | One-page statement of accounts and balances at a date. |
| **Page setup** | Paper size, orientation, margins, header and footer (title, date, page numbers). |
| **File ▸ Print… (⌘P)** and **File ▸ Export as PDF…** | Work from the front window, with a preview. |

How to build it so each screen does not need its own printing code:

- Make each printable thing a SwiftUI "report page" view that takes its data and a paper size.
- Render pages with `ImageRenderer` into PDF, with page breaks for long lists. Keep headers repeating on each page.
- Print through the standard Mac print panel (`NSPrintOperation` over the PDF), and use the same PDF for Save as PDF.
- Use a shared set of print styles (fonts, colours that print well in black and white, table lines).
- Test with long registers (thousands of rows) for speed and page breaks.

## Should have: reports and everyday features

Pick from this list; each one is small to medium.

- **More reports:** income and expense by category and by payee, monthly cash flow, net worth over time, year-end summary, tax-related category summary.
- **Report options:** date range presets, account and category filters, compare to last period, export the table as CSV.
- **Memorised and recurring transactions:** the register already learns payees; add scheduled repeats (paycheque, rent) with a reminder or auto-entry.
- **Split transactions:** one payment split across several categories.
- **Tags or labels** on transactions, usable in reports.
- **Find and replace** across payees and categories, plus a clean-up of duplicate payees.
- **Import from OFX and QIF files** that people download from their bank website. This is a manual file import, not a bank connection, so it fits the app's promise.
- **Check printing layout** (optional): print checks on standard check stock.

## Nice to have

- Attachments beyond receipts (PDF statements kept with an account).
- Keyboard shortcuts review and more menu commands.
- Accessibility pass (VoiceOver, larger text) for the new screens.
- Settings for default report period and print style.

## Shared data file: two users on one Mac

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

## Order of work

1. **Shared data file prototype (3 to 5 days):** build check-out and check-in on a file in `/Users/Shared` and test it with two real Mac logins (including fast user switching): permissions, bookmarks per login, locks, crashes. This decides the design, and it is the riskiest work, so it goes first.
2. **Shared data file build:** Settings ▸ Data section, last-file bookmark, missing-file screen, locks with who and when, read-only open, take-over for stale locks, safe write-back and crash recovery, and the first-run copy of existing data.
3. **Printing foundation:** shared report page, page setup, Print and Save as PDF commands. Prove it on the register.
4. **Print everywhere:** transaction, budget, bills, reports.
5. **New reports** and report options.
6. **Everyday features:** pick two or three from "Should have" (recurring, splits and OFX/QIF import are the strongest).
7. **Polish:** Help pages and screenshots for every new feature (including Settings ▸ Data), release notes, accessibility check.
8. **Release:** TestFlight, submission, website and listing update.

## Rough effort

| Part | Effort |
|---|---|
| Printing foundation and register | 1 to 2 weeks |
| Print for the other screens | 1 week |
| New reports and options | 1 to 2 weeks |
| Each everyday feature | 3 days to 2 weeks (splits and recurring are the larger ones) |
| Help, screenshots, release | 1 week |

About 5 to 8 weeks part-time for printing, reports and two or three everyday features, plus about 4 to 5 weeks for the shared data file, so 9 to 13 weeks in total. All of it is in 1.1. If the schedule slips, drop items from "Should have" first and keep printing and the shared data file.

## Release housekeeping

- Version 1.1, build number up by one for every upload. Keep the schema at `PiggybankSchemaV1` unless a feature needs a model change (splits, tags and recurring transactions do). If so, add `PiggybankSchemaV2` with a tested migration, and test with a copy of real data first.
- Backup before updating: remind users in the release notes.
- New screenshots for the listing and Help for the new features.
- Update the website product page and the "What's new" text.
- Remove the unused iCloud and push entitlements before the next upload.
- The shared data file changes how the app saves, so the release notes and Help explain it, and tell users to make a `.pig` backup before updating.
- New App Review notes: say the app still has no network access and the data file stays on the Mac.

## Risks

- **Print quality:** long lists, page breaks and different paper sizes. Test on real printers and PDF.
- **Model changes** for splits, tags and recurring transactions need a migration. Keep them small and tested.
- **Scope:** printing and the shared data file are the core of 1.1. Stop adding "Should have" features when the schedule slips.
- **Shared data file:** a damaged or unreadable file (two logins and SQLite side files), data loss during the first-run copy, lost edits if someone takes over a lock, stale locks after crashes, and "where is my file?" questions. Check out and check in, copy first and verify, back up first, and crash tests reduce these.
- **Review:** the new version goes through App Review again. Keep release notes clear and the app free of crashes.

## Decisions needed

1. Which of the "Should have" features come in 1.1 (suggestion: recurring transactions, split transactions, OFX/QIF import)?
2. Are check printing and attachments in or out?
3. Is any model change acceptable in 1.1, or should it be print and report features only?
3b. Shared file: **decided.** One person at a time, across separate Mac logins. Both at once is not planned.
4. Release timing, after 1.0 is approved?
