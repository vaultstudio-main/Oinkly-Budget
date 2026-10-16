# Your data, your file — plan

Drafted 2026-10-15. Nothing here is started. Mac 1.0 ships first.

## Direction

OinklyBudget stays a desktop app. There is no iPhone or iPad version planned, so there is no iCloud sync or family-sharing project either (see "Shelved" at the end). Instead, the app gives people control over where their data lives:

- **Choose where the data file is saved:** the Mac, an external drive, a folder they already back up, a cloud folder they manage themselves.
- **Choose which file to open:** several files if they like (one per household, one per business, a test copy).
- **Know exactly where it is.** One file they can see, copy, back up and move.

This fits the rest of the product: no bank linking, no accounts, nothing leaves the Mac unless the person puts it somewhere. "Your data is a file you control" is a selling point for the listing and the website.

It also changes the plan for 2.0: it is now about the data file and a bigger Mac feature set (printing, PDF, reports), not a second platform.

## What the app does today

- Data lives in a SwiftData store inside the app's sandbox container. The person cannot choose its location.
- `.pig` backup and restore (`DataBackup.swift`) already exports and imports everything as one file. That is the closest thing to a data file now.
- The app is sandboxed with user-selected file read and write access already enabled, which is what opening and saving to chosen locations needs.
- The schema is versioned (`PiggybankSchemaV1`) with an empty migration plan, which is the right base for moving data.
- Startup checks (`BootView`, `StartupChecker`) already decide whether the database opens; this is where "which file?" belongs.

## Design

### The data file

A single file the person names and places, with its own extension (for example `.oinkly`) so it opens in the app on double-click. Two ways to build it:

| Option | How | Pros | Cons |
|---|---|---|---|
| **A. SwiftData store as the document** | Use `DocumentGroup` with SwiftData, or create the `ModelContainer` at the chosen URL. | Least new code. Edits save as you go. | SQLite keeps extra `-wal` and `-shm` files beside the main file. Needs care in synced or removable folders. |
| **B. Package (a folder shown as one file)** | The `.oinkly` file is a package holding the store, receipts, photos and a small info file. | One item in Finder, receipts and photos travel with it, room for metadata and a version number. | A little more code. |

Recommendation: **B**, a package with the SwiftData store inside, opened in place. Receipts and photos already use external storage, so they can sit in the package too.

### Opening, saving and switching

- **First launch:** ask "Where do you want to keep your data?" with a sensible default (Documents) and the option to open an existing file.
- **File menu:** New Data File…, Open…, Open Recent, Save a Copy…, Show in Finder, Move Data File… (relocate the current file).
- **Remember the last file** across launches using a security-scoped bookmark (required by the sandbox). If the file is missing or the drive is not connected, show a clear screen: "Can't find your data file. Locate it, open another, or create a new one." Never silently create an empty database.
- **Switching files:** close the current one cleanly (save and checkpoint), then open the next. Show the file name in the window title.
- **Double-click a `.oinkly` file in Finder** opens it. The existing `.pig` file stays as the interchange and backup format.

### Moving existing users to a file

Users on 1.0 have data inside the container. On the first launch of the new version:

1. Explain what is changing in one screen.
2. Copy their data to a file in a location they pick (default Documents), leaving the original untouched.
3. Verify the copy opens and has the same counts of accounts and transactions.
4. Only then switch the app to use the new file. Keep the old store until the user confirms or for a set period.

Offer a `.pig` backup first. Nothing in this flow deletes data.

### Safety and trust

This is a finance app, so the data file is the highest-risk part of the work.

- **Locking.** Stop two copies of the app, or two Macs, writing to the same file at once. Use a lock file or file coordination, and say who has it open.
- **Cloud folders.** Many people will put the file in iCloud Drive, Dropbox or a similar folder. Sync tools can corrupt a live database if they upload it mid-write. Mitigations: write changes in safe checkpoints, close cleanly, detect "conflicted copy" files, and warn once in Help and on first choosing such a folder. State clearly that the app does not sync, and that the person is responsible for what their sync tool does.
- **Automatic backups.** Optional rolling backups to a second location the person picks, with a retention count. Keep the existing backup reminder.
- **Integrity check on open.** Verify the file opens and the schema version is known; refuse files from a newer version with a clear message.
- **Atomic moves and copies.** Copy then verify then switch, never move-then-hope.
- **Crash recovery.** After a crash, open the file normally; the store's journal handles recovery. Test by killing the app mid-edit.

### Possible later additions

- **Password for the file (encryption at rest).** A real selling point for privacy. SwiftData has no built-in file encryption, so this would mean encrypting the package with CryptoKit and keeping a decrypted working copy while open. It needs its own design, especially for lost passwords.
- **Read-only open** for looking at an old file or an archive.
- **Open on a second Mac** by pointing at the same file on a shared drive, one at a time, thanks to locking.
- **Year-end archive.** Close the books for a year into its own file.

## Phases

| Phase | Work | Rough effort |
|---|---|---|
| 0. Prototype | Create a `ModelContainer` at a chosen URL, reopen via bookmark, test in a cloud folder and on an external drive. Decide package or single store. | 3 to 5 days |
| 1. Core | File menu (New, Open, Open Recent, Save a Copy, Show in Finder), last-file bookmark, missing-file screen, window title, `.oinkly` document type. | 1 to 2 weeks |
| 2. Migration | First-run flow, copy and verify, keep the old store, tests with large data (use `TestData`). | 1 week |
| 3. Safety | Locking, integrity check, automatic backups, cloud-folder warnings, crash tests. | 1 to 2 weeks |
| 4. Polish and release | Help, release notes, website and listing copy, screenshots, TestFlight, submission. | 1 week |

About 4 to 7 weeks part-time. Phase 0 decides most of the risk, so do it first and keep it throwaway.

## Release plan

- **1.0:** ships as is, Friday. Nothing here is started.
- **1.x:** feature releases (printing, PDF, reports). Keep new code from assuming the store lives at a fixed location, and keep model changes minimal.
- **2.0:** the data file release. It is a good candidate for a major version because the app's saving behaviour changes. Pair it with a few headline features so the update has a clear story.
- Mention data-file control on the website and listing only when it ships.

## Risks

- **Data loss.** The biggest. Migration must copy first, verify, and keep the original; backups come first in the user's flow.
- **Sync tools and SQLite.** Real-world corruption risk in cloud folders. Packages, clean checkpoints and clear warnings reduce it but cannot remove it.
- **Sandbox.** Every location needs a user grant and a stored bookmark. Test moving or renaming the file while the app is closed, and unplugging drives.
- **Support load.** "Where is my file?" will become a common question. Show the path in Settings and in the About or file info screen.
- **Schema changes.** Any later model change needs a version bump and migration, and files from older versions must open.

## Decisions needed

1. Single store file or a package (recommended: package)?
2. File extension and name (`.oinkly` is a placeholder; `.pig` stays as the backup format)?
3. Is the data file release 2.0 or a 1.x release?
4. Is a file password in scope for the first data-file release?
5. Where does the default location sit for new users (Documents)?

## Shelved

The iPhone and iPad app, iCloud sync and family data sharing are not planned. The notes on those, including the finding that SwiftData with CloudKit cannot share between Apple IDs, are in the git history (`docs/ios-ipad-plan.md`, commit 68cc13c) in case that changes. The Windows plan was dropped earlier.
