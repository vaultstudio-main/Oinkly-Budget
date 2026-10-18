# OinklyBudget 1.2: plan

Drafted 2026-10-18. Nothing here is started. Work on 1.2 begins right after 1.1 ships, and the shared data file is where it starts.

## Goal

Let two Mac logins share one data file, and finish what 1.1 left for later. The direction stays the same: a full desktop program, no bank linking, no accounts, no network.

## Moved to 1.1: goals tied to accounts

Goals tied to accounts (a savings goal following a checking or savings balance, a debt payoff following a loan) moved into 1.1 on 2026-10-18. See the 1.1 plan.

## Shared data file: two Mac logins, one at a time

Moved here from 1.1 on 2026-10-18. The design is in the 1.1 plan (the "Shared data file" section). A working prototype is saved on the `shared-data-prototype` branch (commits `572a337` and `ea179d4`).

What the prototype already does:

- A shared folder holds one finished data file, a lock and a note about the last save. The app works on a private copy and writes it back in one safe replace, so SQLite's side files never sit in the shared folder.
- Receipts and photos travel with the data (SwiftData keeps them outside the database file).
- The lock records who has it and since when. A lock left by a process that no longer exists is stale at once, and take over is offered.
- Crash recovery keeps unsaved work, or saves it as a separate file if someone else saved meanwhile.
- Saves go back every couple of minutes, when the app is hidden and when it quits. Settings has Choose Folder, Save Now, Close File So Someone Else Can Use It and Stop Sharing. Start-up asks first when someone else has the file.

What it still needs:

1. **A test with two real Mac logins** (permissions, fast user switching). This is the main unknown, and nothing else should be built before it.
2. Open Recent, Move This File and Create a New File.
3. Timing a save on a large data file.
4. Cleaning up receipt files that are no longer used.
5. Help pages and release notes.

The encrypted data file (also deferred) was designed on top of this save path, so plan them together.

Effort: about 2 to 3 weeks from the prototype.

## One database change, done once

Several things want a stored field. Doing them together means one migration instead of several.

| Item | Why it needs a field |
|---|---|
| **Primary checking on the account itself** | 1.1 keeps it as a setting on the Mac. As a field it travels with backups and the shared data file. |
| **Split transactions** | One payment across several categories. |
| **Recurring transactions** | Paycheque, rent and so on, with a reminder or an automatic entry. |
| **Tags** on transactions | Usable in reports. |

The catch: the database is declared as `PiggybankSchemaV1`, and a new `PiggybankSchemaV2` needs a frozen copy of all ten models as they are in 1.1, plus a tested migration between them. That is the biggest part of the work. Plan it as its own step first:

- Back up before updating; make the migration test part of release testing.
- Test the migration on copies of real data, including a large one.
- Keep every change a field with a default, so the migration stays an automatic, lightweight one.

Splits, recurring and tags are in the 1.1 "Should have" list. Anything not built in 1.1 moves here and uses this migration. Effort: about 1 week for the migration itself, then 3 days to 2 weeks for each feature.

## Finish what 1.1 left

- **PDF for more pages.** The builders for net worth, bills, reports and the budget are written, but no page has a button for them. Decide where they go, if anywhere.
- **Check printing layout** (optional): print checks on standard check stock.
- **Attachments beyond receipts:** PDF statements kept with an account.
- **Keyboard shortcuts review** and more menu commands.
- **Accessibility pass** (VoiceOver, larger text) for the screens added in 1.1 and 1.2.
- **Settings for default report period, paper size and export style.**
- **Widgets:** more sizes or a configurable widget (choose which bills or reminders) if people ask for it.

## Release housekeeping

- Version 1.2, build number up by one for every upload.
- Help pages and screenshots for each new feature, release notes, website and listing update.
- A schema change means the release notes and Help tell users to make a `.pig` backup before updating.
- New App Review notes if anything changes about data handling.

## Rough effort

| Part | Effort |
|---|---|
| Database migration (V2) | about 1 week |
| Each stored-field feature (splits, recurring, tags) | 3 days to 2 weeks |
| PDF pages, attachments, accessibility, settings | 1 to 2 weeks |
| Help, screenshots, release | 1 week |

About 5 to 8 weeks part-time. If it slips, drop the optional items first and keep the shared data file and the migration.

## Risks

- **The migration.** An existing database that can't open is the worst outcome. Back up first, test on copies, and keep every change a defaulted field.
- **Scope.** The shared data file is the headline. Don't let the optional list crowd it out.

## Decisions needed

1. Shared data file: when two real Mac logins can test it.
2. Which of splits, recurring and tags are built in 1.1 and which move here.
3. Where the extra PDFs (net worth, bills, reports, budget) belong, if anywhere.
4. Release timing, after 1.1 is approved.
