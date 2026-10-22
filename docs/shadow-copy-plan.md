# Shadow copy (branch `shadow-copy`, not in `main`)

An exploration branch, started 2026-10-22. `main` stays as it is. If this proves worth it, it is merged into `main` (for 1.0 or 1.1).

## What it is

A second, separate copy of the data in a folder the person chooses (Documents, iCloud Drive, a drive), kept up to date by the app. Alone it copies this Mac's data; while sharing it copies the working copy each time the shared data is saved, so it matches the shared data. The app never runs on the shadow copy and never writes over the data from it without asking.

## Decisions (the recommended ones)

- **Format:** a checked snapshot of the data file plus the receipts (not a `.pig`): exact, fast, written in the background. `.pig` stays the manual backup.
- **When:** a few minutes after changes, when the app is hidden, and on quit. In sharing: after every save of the shared data.
- **Kept:** the latest copy, the newest 10 older copies, plus one per day for a week.
- **Status:** a separate label next to the other dots, always in words: green "Copied 5 min. ago", yellow "Copying…", orange "Not set up / Out of date / Folder not found / Other data", red "Problem". Clicking it opens Settings ▸ Data & Backup.
- **Asking:** once the person has added some data, a sheet explains it (including that it is not encrypted); "Not now" waits a week, "Don't ask again" stops it.
- **Erase All Data:** offers "Erase Everything and Delete the Shadow Copy" next to the plain erase, which leaves the shadow copy so the erase can be undone.
- **Privacy:** plain, unencrypted copy; the setup sheet, the Settings footer and a Read Me in the folder say so.

## Where the files are

`<chosen folder>/Oinkly Budget Shadow Copy/`: `OinklyBudget.store` (latest), `shadow.json` (which copy, how many accounts and transactions, which shared save it matches), `Older copies/`, a hidden receipts folder, `Read Me.txt`. Owner-only permissions.

## What is built (stage 1)

- `Logic/ShadowCopy/ShadowFolder.swift`: writing (copy beside, check against the original, then swap), older copies and pruning, integrity check, restore, and `ShadowCheck`: the checks of this Mac's data and of the shared data against the shadow copy.
- `Logic/ShadowCopy/ShadowCopyManager.swift`: the folder permission (remembered), the automatic copying, status, a restore that happens before the data is opened (with a safety copy first).
- `Views/ShadowCopyViews.swift`: the status label, the first-time sheet, Settings ▸ Data & Backup ▸ Shadow Copy with a restore list, and the start-up screen offered when the data is empty, much smaller, or unreadable while the shadow copy has plenty.
- `StartupState.isHoldingPlace`: while the app is on a stand-in database, reminders, notifications, the widget file and the shadow copy are left alone (this closes the problem found in the menu review, on this branch only).
- Tests: hardening test S25 (26 checks).

## Not done yet (stage 2)

- Sharing: the checks against the shared data exist and are tested (`lookAtSharedData`) but are not yet shown on the waiting screen, and there is no "rebuild the shared folder from the shadow copy" yet.
- "Restore from a shadow copy" on the setup screen, for a new Mac.
- Help topic and release notes.
- The status label's Settings link, the folder permission across a restart, the quit-time copy, the restore and the rescue screen have been built and the logic tested, but not yet tried by hand in the running app.
- Speed and size with a large data file, and with the folder in iCloud Drive.
- Whether to put the receipts clean-up (old receipts nothing uses) into the shadow folder.
