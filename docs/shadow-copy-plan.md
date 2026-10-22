# Backup copy (branch `shadow-copy`, not in `main`)

An exploration branch, started 2026-10-22. `main` stays as it is. If this proves worth it, it is merged into `main` (for 1.0 or 1.1).

## What it is

A second, separate copy of the data in a folder the person chooses (Documents, iCloud Drive, a drive), kept up to date by the app. Alone it copies this Mac's data; while sharing it copies the working copy each time the shared data is saved, so it matches the shared data. The app never runs on the backup copy and never writes over the data from it without asking.

## Decisions (the recommended ones)

- **Format:** a checked snapshot of the data file plus the receipts (not a `.pig`): exact, fast, written in the background, then sealed in Oinkly Budget's own file format (below). `.pig` stays the manual backup.
- **When:** a few minutes after changes, when the app is hidden, and on quit. In sharing: after every save of the shared data.
- **Kept:** the latest copy, the newest 10 older copies, plus one per day for a week.
- **Status:** one combined label for this Mac's database and the backup copy, called "Backup Copy Database", in the bottom bar. The worst state wins: red "Database · Problem" or "Backup Copy · Problem", then orange for the backup copy (Not set up, Out of date, Folder not found, Other data), then yellow (Saving…, Copying…), then green "Copied 5 min. ago". Without a backup copy set up it shows the orange Not set up nudge. While sharing, the Shared dot is separate and this one only reports a database problem. Clicking it opens Settings ▸ Data & Backup.
- **Asking:** once the person has added some data, a sheet explains it (including that it is not encrypted); "Not now" waits a week, "Don't ask again" stops it.
- **Erase All Data:** offers "Erase Everything and Delete the Backup Copy" next to the plain erase, which leaves the backup copy so the erase can be undone.
- **Privacy:** the files are in Oinkly Budget's own format but not encrypted (a wrapper keeps out casual readers, not someone determined); the setup sheet, the Settings footer and Help say so.

## Where the files are

`<chosen folder>/Oinkly Budget Backup Copy/`: `OinklyBudget.pigdata` (latest), `Older copies/` (`copy N <date>.pigdata`), `Receipts/` (each receipt or photo as its own `.pigdata`). Nothing is plain text, JSON or a database file. Owner-only permissions.

**Sealed format (`SealedFile`)**: a fixed Oinkly marker, a binary property list header (kind, date, app version, size and the notes: which copy, how many accounts and transactions, which shared save it matches), the body compressed with LZFSE, and a SHA-256 fingerprint of the body. A text editor or database viewer shows nothing useful; only Oinkly Budget unpacks it; a changed or cut-short file is noticed from its fingerprint without opening it. It is a wrapper, not encryption: someone who studies the app's code could unpack it. `.pigdata` is registered as an Oinkly Budget file type, so double-clicking one opens the app and offers to restore from it.

## What is built (stage 1)

- `Logic/ShadowCopy/ShadowFolder.swift`: writing (copy beside, check against the original, then swap), older copies and pruning, integrity check, restore, and `ShadowCheck`: the checks of this Mac's data and of the shared data against the backup copy.
- `Logic/ShadowCopy/ShadowCopyManager.swift`: the folder permission (remembered), the automatic copying, status, a restore that happens before the data is opened (with a safety copy first).
- `Views/ShadowCopyViews.swift`: the status label, the first-time sheet, Settings ▸ Data & Backup ▸ Backup Copy with a restore list, and the start-up screen offered when the data is empty, much smaller, or unreadable while the backup copy has plenty.
- `StartupState.isHoldingPlace`: while the app is on a stand-in database, reminders, notifications, the widget file and the backup copy are left alone (this closes the problem found in the menu review, on this branch only).
- Tests: hardening test S25 (26 checks).

## Built in stage 2

- Sharing: the checks against the shared data run before the shared data is opened. Missing, damaged, older, or different shared data stops the app on the waiting screen with the choices: restore from the backup copy (the newest good one or an older one), use the newest good earlier save in the shared folder, open the shared data as it is, or use this Mac's own data. Putting data back keeps what was there as an earlier save, takes the lock first, and carries on the backup copy's numbering and data ID (`SharedRescue`).
- "Restore… Copy" on the setup screen, for a new Mac: choose the folder that holds the backup copy; the restore happens at the next start and the backup copy's data ID is adopted.
- Help topic "Backup Copy" and a release notes line.
- Hardening test S26 (12 checks). One earlier test (S17) was made stricter about amounts, because it could fail by chance on an ID that contained "1234".

## Built in stage 3

- The sealed file format and the backup copy on it (every file sealed, receipts included), hardening test S28 (15 checks).
- The `.pigdata` file type and the restore offer when one is opened from Finder.
- Turning sharing on asks for a backup copy folder too ("to keep the peace between your edits and the other person's"), with "Share Without a Backup Copy" as the other choice.

## Built in stage 4

- **`.pig` backups are sealed** with the same wrapper (kind "backup"); old plain JSON `.pig` files still open. The `.pig` file type now conforms to plain data, not JSON.
- **The shared folder is in the sealed format (format 2):** the data and every previous save and recovered copy are `.pigdata`; each file's note (revision, who saved, record counts, the receipts it uses) lives in its header, so the data and its note can't get out of step; the lock, the log and the members notes are binary `.pigmeta` files; receipts are sealed in a `Receipts/` folder. Receipt clean-up reads the receipts each save lists in its note, and stops if any save's note can't be read.
- **Existing shared folders are converted once** by whoever opens them first, holding the lock: receipts, previous saves, recovered copies and the log are converted first and the data file is put in place last, so a conversion that is cut short leaves the old data untouched and is redone. A lock written by an older copy of the app still counts. Damaged old data is refused and left alone.
- Hardening test S29 (21 checks) covers the conversion; S1 to S11 were updated for the sealed files. All 180 hardening checks, the self test and the timing test pass.

## Built in stage 5

- **Renamed:** the shadow copy is now the **Backup Copy** everywhere people see it (status "Backup Copy Database · Copied 5 min. ago", Settings, Help, the setup and Share windows, the folder "Oinkly Budget Backup Copy", which is moved over from the old name). The manual `.pig` buttons are **Export Data** and **Import Data**, under their own "Export & Import" section below the Backup Copy. The backup reminder now points to the Backup Copy and stays quiet once one is set up.
- **A portable `.pig` file beside each snapshot:** the snapshot is the exact copy; the portable file (sealed, kind "backup") carries everything including the settings and works across versions. It is made about once a day (timed copies), always when quitting and on Copy Now, and kept to the newest five in `Portable files/`. It is only written when it matches the snapshot made at the same moment (same accounts and transactions), otherwise the next copy makes one.
- **Cost:** reading all the data into a backup takes the main thread (the models can't be read elsewhere): 2.7 s for 20,000 transactions in the timing test, so roughly 14 s at 100,000. The app measures it, and when it takes over 1.5 s the timed copies skip the portable file and leave it to quitting and Copy Now. Sealing and writing happen in the background and take well under a second.
- **Restoring:** the Restore list shows snapshots, then portable files. When no snapshot is usable the start-up screen offers the portable file; a portable restore happens at the next start into a fresh data file, after a safety copy. The setup screen has one **Restore…** button that takes a `.pig` file, a `.pigdata` copy, or the backup copy folder.
- Hardening test S31 (11 checks); 197 hardening checks pass in all.

## Built in stage 6

- **The portable file is about four times faster to build:** transactions are read in one fetch instead of account by account (2.7 s to 0.73 s for 20,000 transactions in the timing test; the two ways give identical transactions). Roughly a second for every 25,000. The timed copies still skip the portable file once a build takes over 1.5 s (about 40,000 transactions); quitting and Copy Now always make one.
- **Receipt clean-up in the backup copy:** each copy's note lists the receipts it uses; a receipt is removed after 30 days when neither the latest copy nor any older copy uses it, and nothing is removed if any copy's note can't be read. Portable files carry their receipts inside, so they don't count.
- **Settings layout** checked from a picture of the page (with and without a backup copy): Copy Now, Restore… and Show in Finder stay on the row, Change Folder… and Turn Off… moved into a More menu, the footer says what is made and when, and the row says "Snapshots kept".
- Hardening test S32 (6 checks): 203 in all.

## Changed after stage 6

- **Settings ▸ Backup Copy is a switch.** Keep a Backup Copy on or off; when on it shows Status (Up to date, Saving a copy…, Changes are waiting to be copied, folder problems), Folder and Last copied, with Copy Now, Restore…, Show in Finder and Change Folder…. The long footer, the version counts and the More menu were removed. Turning it off asks whether to delete the Oinkly Budget Backup Copy folder too (to the Trash) or keep it.

- **Settings order:** Backup Copy (switch), Sharing (now a switch too, with Save Now, Save and Quit, Previous Saves… and Check Sharing… under it when on; turning it on or off asks first as before), then **Export & Import** as two plain buttons, Export Data… and Import Data…, then Erase All Data and About.

## Not done yet

- Older builds can't open a converted folder (they look for the old file names): update both logins' test builds together.

- The status label's Settings link, the folder permission across a restart, the quit-time copy, the restore and the rescue screen have been built and the logic tested, but not yet tried by hand in the running app.
- Speed and size with a large data file, and with the folder in iCloud Drive.
- Whether to put the receipts clean-up (old receipts nothing uses) into the shadow folder.
