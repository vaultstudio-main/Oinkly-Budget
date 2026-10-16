# One shared data file on one Mac — plan

Drafted 2026-10-15. Nothing here is started. Mac 1.0 ships first.

## Goal

Keep it basic. One OinklyBudget data file, kept wherever the household chooses on the Mac, that several people can open **one at a time**. No sync, no cloud, no iPhone or iPad version, no accounts, no profiles inside the file.

## What this means

- The data is a file, not something hidden in the app's private storage. People choose where it lives and can see it in Finder.
- Anyone using the Mac can open that same file and see the same accounts, bills and budgets.
- Only one person edits at a time. Others who try to open it are told who has it and can wait, open it read-only, or open a different file.

## Two situations, same feature

| Situation | Notes |
|---|---|
| **Everyone shares one Mac login** (or takes turns in the same account) | Simplest. The file can sit in Documents. |
| **Each person has their own Mac login** | The file has to live somewhere every login can reach, such as `/Users/Shared`. Each person opens it once with the Open dialog so the app is allowed to use it. This case needs extra care (see below). |

## The simple version

1. **The data file** is named and placed by the person (default: Documents). It has its own extension (placeholder `.oinkly`) so double-clicking it in Finder opens it. The `.pig` backup stays as the backup format.
2. **File menu:** New Data File…, Open…, Open Recent, Show in Finder, Move Data File… The file name shows in the window title.
3. **Open the last file at launch.** If it is missing, say so ("Can't find your data file. Locate it, open another, or create a new one") and never start an empty database silently.
4. **One person at a time.** Opening a file puts a small lock beside it saying who has it (Mac user name) and since when. A second person sees "Sam has this file open since 3:10 PM" and can choose: Open Read-Only, Open Another File, or Cancel. The lock is released when the file closes or the app quits.
5. **Stale locks.** After a crash or power cut the lock is left behind. If the lock is old and the app that wrote it is no longer running, offer "Take Over", with a warning.
6. **Quick hand-off.** A File menu item, "Close File So Someone Else Can Use It", saves, releases the lock, and returns to the open screen.
7. **Existing users keep their data.** On the first launch of the new version, copy the data from where it is now into a file the person chooses, check the counts match, and keep the original untouched. Offer a `.pig` backup first.

## The main technical risk: two logins sharing one database

SwiftData stores data in a SQLite database, which creates extra files (`-wal`, `-shm`) while the app runs. Files created by one Mac login can be read-only to another login, so the second person's app may fail to open or write the file. A shared folder, a database in write-ahead mode, and two different owners is the classic way to get errors or damaged data.

Recommended design, safe and simple: **check out and check in**.

- **Opening** takes the lock, then copies the shared file to a private working copy in the app's own storage and edits that.
- **Saving and closing** writes the working copy back to the shared file in one safe step (write a new file, then replace the old one), then releases the lock.
- The shared file is only ever a finished, closed file, never a live database, so permissions and sync tools cannot damage it mid-write.
- The app sets the shared file so every login can read and write it.
- **Crash recovery:** if the app starts and finds a working copy that was never written back, offer to recover it into the shared file or discard it.
- **Autosave:** write back on a timer and when the app goes to the background, so a crash loses little.

The cost is that the shared file is only as current as the last write-back. That is fine for one-at-a-time use.

A simpler alternative, opening the shared file live with SwiftData, is easier to build and fine if everyone shares one login. It is risky across logins, so test it in the prototype before choosing.

## Left out on purpose

- Passwords or separate permissions per person (a data file password could come later).
- Syncing between Macs. If someone keeps the file in iCloud Drive or Dropbox, that is their choice. The Help page says the app does not sync and to close the file before copying it.
- Several people editing at the same time.

## Other technical notes

- The app is sandboxed with user-selected file access on. It needs a stored bookmark of the last file to reopen it. Bookmarks are per Mac login, so each person opens the shared file once.
- The schema is versioned (`PiggybankSchemaV1`). Older files open and are upgraded; newer files are refused with a clear message.
- Show the file path in Settings, since "where is my file?" will be the common question.
- Optional: show "Last saved by <user> at <time>" in the file info.

## Phases

| Phase | Work | Rough effort |
|---|---|---|
| 0. Prototype | Open a store at a chosen location from a bookmark; try the check-out and check-in copy; try a second Mac login on a file in `/Users/Shared`. Decide live versus check-out. | 3 to 5 days |
| 1. Core | File menu, document type, last-file bookmark, missing-file screen, window title, Save a Copy. | 1 week |
| 2. Sharing | Lock file with who and when, read-only open, hand-off item, stale-lock take-over, permissions on the shared file. | 1 week |
| 3. Safety | Check-in and recovery, autosave write-back, crash tests (kill the app mid-edit, with and without a lock). | 1 week |
| 4. Migration | First-run copy, verify, keep the original, test with large data. | 3 to 5 days |
| 5. Release | Help, release notes, website and listing copy, screenshots. | 3 to 5 days |

About 4 to 5 weeks part-time.

## Release plan

- **1.0:** ships as is. Nothing here is started.
- **1.x:** printing, PDF and report features. Avoid assuming the data lives in a fixed place.
- **Data-file release:** a 1.x or 2.0 release, your call. Mention it on the website and listing only when it ships.

## Risks

- **Damaged or unreadable file** from two logins and SQLite side files. Mitigated by check-out and check-in.
- **Data loss during the move to a file.** Copy first, verify, keep the original, back up first.
- **Lost edits** if someone takes over a lock while the first person is still working. The take-over warning must be clear.
- **Stale locks** after crashes. Test them.
- **Later model changes** need a version bump and migration, and older files must still open.

## Decisions needed

1. Check-out and check-in (recommended) or open the shared file live?
2. Is the first release for people sharing one login only, or must it work across separate Mac logins?
3. Is the data-file release 1.x or 2.0?
4. Is a file password in scope for the first version?

## Shelved

The iPhone and iPad app, iCloud sync, family data sharing, Windows and profiles inside one file are not planned. The iOS notes, including that SwiftData with CloudKit cannot share between Apple IDs, are in git history (`docs/ios-ipad-plan.md`, commit 68cc13c).
