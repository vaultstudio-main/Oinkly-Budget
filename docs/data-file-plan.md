# One Mac, more than one person — plan

Drafted 2026-10-15. Nothing here is started. Mac 1.0 ships first.

## Goal

Keep it basic. Several people can use OinklyBudget on the same Mac, and each one has their own data. No sync, no cloud, no iPhone or iPad version, no accounts.

The way to do it is to let people choose which data file the app uses and where it is saved.

## What already works

macOS keeps each user's app data separate. If two people have their own Mac logins, they already have separate OinklyBudget data and nothing needs to be built. This plan is for people who **share one Mac login**, or who want to **share one file between logins**.

## The simple version

1. **The data is a file** the person can name and put anywhere on the Mac (default: Documents).
2. **A "Who's using it?" screen at launch** lists the data files the app knows (Open Recent), with Open Another… and New… Pick one and the app opens it. If there is only one file, skip the screen.
3. **File menu:** New Data File…, Open…, Open Recent, Show in Finder. Switching closes the current file cleanly and opens the next. The file name shows in the window title.
4. **One person at a time per file.** If a file is already open (in this app or another login), say so and offer to open it read-only or pick another file. This is a simple lock file next to the data.
5. **Existing users keep their data.** On the first launch of the new version, copy the data from where it is now into a file the person chooses, check the counts match, and keep the original untouched. Offer a `.pig` backup first.

That is the whole feature. Each person gets their own file, and sharing one file is possible by putting it somewhere both logins can reach, such as `/Users/Shared`, one at a time.

## Left out on purpose

- Passwords or locking by person inside the app (a data file password could come later).
- Cloud syncing. If someone keeps their file in iCloud Drive or Dropbox, that is their choice, and the Help page says the app does not sync and to close the app before copying the file.
- Sharing between different Macs at the same time.

## Small technical notes

- The app is sandboxed with user-selected file access already on. It needs a stored bookmark for the last file so it can reopen it next time. If the file is missing, show "Can't find your data file. Locate it, open another, or create a new one." Never start an empty database silently.
- Schema is versioned (`PiggybankSchemaV1`), so older files can be opened and newer files refused with a clear message.
- The `.pig` backup stays as the backup format. The new data file gets its own extension (a placeholder: `.oinkly`) so double-clicking it in Finder opens it.
- A single SwiftData store file is enough for this simpler goal. Receipts and photos already use external storage and would sit beside it, so a package (a folder that looks like one file) is a small step up and worth considering.

## Phases

| Phase | Work | Rough effort |
|---|---|---|
| 0. Prototype | Open the SwiftData store at a chosen location and reopen it from a bookmark. | 2 to 3 days |
| 1. Core | File menu, last-file bookmark, missing-file screen, window title, document type. | 1 week |
| 2. Chooser and lock | "Who's using it?" screen, lock file, read-only option. | 3 to 5 days |
| 3. Migration | First-run copy, verify, keep original. Test with large data. | 3 to 5 days |
| 4. Release | Help, release notes, website and listing copy, screenshots. | 3 to 5 days |

About 3 to 4 weeks part-time.

## Release plan

- **1.0:** ships as is. Nothing here is started.
- **1.x:** printing, PDF and report features. Avoid assuming the data lives in a fixed place.
- **Data-file release:** a 1.x or 2.0 release, your call. Mention it on the website and listing only when it ships.

## Risks

- **Data loss during the move.** Copy first, verify, keep the original, back up first.
- **Two people editing one file.** The lock file prevents this. Test a crash that leaves a stale lock.
- **"Where is my file?" support questions.** Show the file path in Settings.
- **Later model changes** need a version bump and migration, and older files must still open.

## Decision needed

What does "multi user on one Mac" mean for you?

1. **Separate data for each person** sharing one Mac login (recommended, this plan).
2. **One shared file** that several people on the same Mac open one at a time.
3. **In-app user profiles** inside a single file, with each person seeing only their own accounts.

## Shelved

The iPhone and iPad app, iCloud sync, family data sharing and Windows are not planned. The iOS notes, including that SwiftData with CloudKit cannot share between Apple IDs, are in git history (`docs/ios-ipad-plan.md`, commit 68cc13c).
