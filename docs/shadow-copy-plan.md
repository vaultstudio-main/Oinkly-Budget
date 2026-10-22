# Shadow copy (branch `shadow-copy`, not in `main`)

An exploration branch, started 2026-10-22. `main` stays as it is. If this proves worth it, it is merged into `main` (for 1.0 or 1.1).

## What it is

A second, separate copy of the data in a folder the person chooses (Documents, iCloud Drive, a drive), kept up to date by the app. Alone it copies this Mac's data; while sharing it copies the working copy each time the shared data is saved, so it matches the shared data. The app never runs on the shadow copy and never writes over the data from it without asking.

## Decisions (the recommended ones)

- **Format:** a checked snapshot of the data file plus the receipts (not a `.pig`): exact, fast, written in the background, then sealed in Oinkly Budget's own file format (below). `.pig` stays the manual backup.
- **When:** a few minutes after changes, when the app is hidden, and on quit. In sharing: after every save of the shared data.
- **Kept:** the latest copy, the newest 10 older copies, plus one per day for a week.
- **Status:** one combined label for this Mac's database and the shadow copy, called "Shadow Copy Database", in the bottom bar. The worst state wins: red "Database · Problem" or "Shadow Copy · Problem", then orange for the shadow copy (Not set up, Out of date, Folder not found, Other data), then yellow (Saving…, Copying…), then green "Copied 5 min. ago". Without a shadow copy set up it shows the orange Not set up nudge. While sharing, the Shared dot is separate and this one only reports a database problem. Clicking it opens Settings ▸ Data & Backup.
- **Asking:** once the person has added some data, a sheet explains it (including that it is not encrypted); "Not now" waits a week, "Don't ask again" stops it.
- **Erase All Data:** offers "Erase Everything and Delete the Shadow Copy" next to the plain erase, which leaves the shadow copy so the erase can be undone.
- **Privacy:** plain, unencrypted copy; the setup sheet, the Settings footer and a Read Me in the folder say so.

## Where the files are

`<chosen folder>/Oinkly Budget Shadow Copy/`: `OinklyBudget.pigdata` (latest), `Older copies/` (`copy N <date>.pigdata`), `Receipts/` (each receipt or photo as its own `.pigdata`). Nothing is plain text, JSON or a database file. Owner-only permissions.

**Sealed format (`SealedFile`)**: a fixed Oinkly marker, a binary property list header (kind, date, app version, size and the notes: which copy, how many accounts and transactions, which shared save it matches), the body compressed with LZFSE, and a SHA-256 fingerprint of the body. A text editor or database viewer shows nothing useful; only Oinkly Budget unpacks it; a changed or cut-short file is noticed from its fingerprint without opening it. It is a wrapper, not encryption: someone who studies the app's code could unpack it. `.pigdata` is registered as an Oinkly Budget file type, so double-clicking one opens the app and offers to restore from it.

## What is built (stage 1)

- `Logic/ShadowCopy/ShadowFolder.swift`: writing (copy beside, check against the original, then swap), older copies and pruning, integrity check, restore, and `ShadowCheck`: the checks of this Mac's data and of the shared data against the shadow copy.
- `Logic/ShadowCopy/ShadowCopyManager.swift`: the folder permission (remembered), the automatic copying, status, a restore that happens before the data is opened (with a safety copy first).
- `Views/ShadowCopyViews.swift`: the status label, the first-time sheet, Settings ▸ Data & Backup ▸ Shadow Copy with a restore list, and the start-up screen offered when the data is empty, much smaller, or unreadable while the shadow copy has plenty.
- `StartupState.isHoldingPlace`: while the app is on a stand-in database, reminders, notifications, the widget file and the shadow copy are left alone (this closes the problem found in the menu review, on this branch only).
- Tests: hardening test S25 (26 checks).

## Built in stage 2

- Sharing: the checks against the shared data run before the shared data is opened. Missing, damaged, older, or different shared data stops the app on the waiting screen with the choices: restore from the shadow copy (the newest good one or an older one), use the newest good earlier save in the shared folder, open the shared data as it is, or use this Mac's own data. Putting data back keeps what was there as an earlier save, takes the lock first, and carries on the shadow copy's numbering and data ID (`SharedRescue`).
- "Restore from a Shadow Copy" on the setup screen, for a new Mac: choose the folder that holds the shadow copy; the restore happens at the next start and the shadow copy's data ID is adopted.
- Help topic "Shadow Copy" and a release notes line.
- Hardening test S26 (12 checks). One earlier test (S17) was made stricter about amounts, because it could fail by chance on an ID that contained "1234".

## Built in stage 3

- The sealed file format and the shadow copy on it (every file sealed, receipts included), hardening test S28 (15 checks).
- The `.pigdata` file type and the restore offer when one is opened from Finder.
- Turning sharing on asks for a shadow copy folder too ("to keep the peace between your edits and the other person's"), with "Share Without a Shadow Copy" as the other choice.

## Not done yet

- The shared folder still uses plain files (`OinklyBudget.store`, `info.json`, `lock.json`, `members`, `previous saves`, `save log.txt`). Putting those into the same sealed format needs a one-time conversion of existing shared folders and changes the most-tested code, so it is the next step. `.pig` backups are still JSON.

- The status label's Settings link, the folder permission across a restart, the quit-time copy, the restore and the rescue screen have been built and the logic tested, but not yet tried by hand in the running app.
- Speed and size with a large data file, and with the folder in iCloud Drive.
- Whether to put the receipts clean-up (old receipts nothing uses) into the shadow folder.
