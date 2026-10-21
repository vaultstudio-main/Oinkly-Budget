# Shared data file: design (step 5)

Drafted 2026-10-18. Nothing here is built yet. This is the design for the last and riskiest feature of 1.0. It lists how the feature works, every decision that is still open (with options and a recommendation), how it fits the V2 database and the encryption vault, what can go wrong, how each failure is handled, and the order of work with a stop point after the first risky test. The decisions are in section 12. Build starts after they are answered.

## 1. Goal and limits

**Goal.** Two or more people who each have their own Mac login on **one Mac** can use the same Oinkly Budget data file, **one at a time**. There is no cloud, no sync, no account in the app and no network.

**What it is not.**
- Not two people editing at the same moment. Both at once needs merging, which is a different and much riskier feature. Not planned.
- Not sync between different Macs or an iPhone.
- Not a way to put the live database in a cloud-synced or network folder (see decision D10).

**The promise (from the data integrity plan).** Sharing never loses a client's information: the shared file is only ever replaced with a file that has been checked, there is always a previous copy, a crash keeps unsaved work, and a failure leaves the old file exactly as it was.

## 2. What exists today

- **The prototype** on branch `shared-data-prototype` (commits `572a337`, `ea179d4`) works on the old V1 database and no encryption. It has: a shared folder (`SharedDataFolder`) with one finished data file, a lock, an info note and a "previous save" copy; the session (`SharedDataSession`) that checks the file out to a private working copy at launch and checks it back in every couple of minutes, when hidden and at quit; crash recovery with a marker; a "someone has the file" decision screen; and a debug test folder.
- **The vault** (`VaultSession`, on `main`) already does encryption with the same shape: an encrypted vault file, a private working copy, a sealing step, a marker, a timer. It was written to be reused here. Today the vault lives in this Mac's own Application Support.
- **V2** (the new database shape) and the **safety copy** and **data file location fix** are in.

So the work is: bring the prototype up to V2, make it and the vault one system instead of two, finish what the prototype lacks, and test it with two real logins.

## 3. How it works (the core idea)

The shared file is **checked out and checked in**, never opened live. SQLite makes side files while running, and two logins share no memory, so opening one live database from two logins would corrupt it.

1. **A shared folder** holds a finished data file (or an encrypted vault), a lock, and a note about the last save.
2. **Opening** takes the lock, then copies the finished file into a private working copy in the app's own storage. The app runs on the working copy like any database.
3. **Saving** writes the working copy back to the shared folder as a complete new file in one safe replace, after checking it. The old file is kept as the previous save.
4. **Closing** saves one last time and lets go of the lock.
5. **A crash** leaves the working copy and a marker. The next launch keeps that work.

This is the prototype's design and it stays.

## 4. What lives in the shared folder

```
<Shared folder>/
  OinklyBudget.store              the finished data file (plain mode)
  .OinklyBudget_SUPPORT/          receipts and photos (SwiftData keeps them outside the file)
  OinklyBudget.vault              the finished encrypted file (encrypted mode, replaces the .store)
  OinklyBudget.vaultkeys          the wrapped key (encrypted mode); useless without the passphrase or recovery key
  info.json                       format version, schema version, revision, saved at, saved by, app version, encrypted or not, file ID
  lock.json                       who has it, since when, last heartbeat, process and Mac
  previous saves/                 the last few finished files (see D8)
  Oinkly Budget (recovered ...)    a copy kept when a crash and someone else's save overlapped
```

New compared with the prototype: `schemaVersion`, `revision` (a counter that goes up by one at every save, replacing the date comparison the prototype used, which loses precision), `encrypted`, and a `fileID` so a folder swapped for a different one is noticed.

## 5. Each login's own storage

Per login, in that login's own container: the working copy, the marker, the remembered key (Keychain), the folder bookmark, and the app's settings (currency, appearance, reminders, paper and style). **Settings are per login on purpose**; the data is shared, not the preferences (see D9).

## 6. The key risks, and what we know about them

### 6.1 Permissions between logins (the biggest unknown)

- `/Users/Shared` is a "sticky" folder: only the owner of a file may rename or delete it. A second login could then **not** replace the first login's data file. The app must therefore make its **own subfolder** with open permissions (no sticky bit), which the prototype does (`0777`), and make every file readable and writable by all (`0666`).
- The app is sandboxed. Under the owner's decision (D15, 12b) the folder is fixed and reached through a narrow sandbox exception, with a one-click panel and bookmark as the fallback if App Review refuses the exception.
- Whether the sandbox lets the app change permissions on a folder another login created, and whether the replace works across logins, **has never been tested with two real logins**. This is the first thing to test (Phase 0).
- The "is that process still running" check (`kill(pid, 0)`) may not work from the sandbox. If it can't tell, only the heartbeat decides a lock is stale (3 minutes).

### 6.2 Two copies starting together

The prototype writes the lock and then looks again after 0.15 seconds. Better: create `lock.json` with an **exclusive create** (`O_CREAT | O_EXCL`), which only one process can win, and take over a stale lock by replacing it only if it still holds the stale token. No sleep-and-look.

### 6.3 Sleep, fast user switching and idle logins

- A login that is switched away can still be running with the app open and holding the lock. Its heartbeat keeps going, so it looks alive. The other login sees a waiting message and the app opens by itself when the file is free (D17).
- A laptop that sleeps stops the heartbeat. After 3 minutes another login may take over. When the first one wakes, it must **notice at once** (check the lock on wake), stop saving, keep its working copy, and keep its unsaved work as a recovered copy. The prototype only notices at the next heartbeat.

### 6.4 Receipts and photos

SwiftData keeps large files outside the database, in a hidden folder beside it. They must travel with the data. The prototype copies only new files, which is safe, but never deletes, so unused receipts pile up. The design: copy new files **before** the database is replaced; remove files no longer used only at a clean close and only after they have been unused for 30 days (so the previous save still works).

### 6.5 Size and speed

Each save is a `VACUUM INTO` plus record counts plus an integrity check. That is fine for thousands of transactions and unknown for 100,000. Measure first (Phase 3). If slow: save less often (every 5 minutes), run the full integrity check only on close, and always run it off the main thread (the prototype does).

### 6.6 Where the folder is

A folder on this Mac's disk is fine. A network share, a cloud-synced folder (iCloud Drive, Dropbox) or an external drive that gets unplugged brings extra risks. See D10.

## 7. Encryption and sharing together

One system, not two. Four data locations, one pipeline:

| Location | Plain or encrypted | The finished file is |
|---|---|---|
| This Mac only | plain | the default store (today's behaviour) |
| This Mac only | encrypted | the vault in Application Support (today's behaviour) |
| Shared folder | plain | `OinklyBudget.store` in the shared folder |
| Shared folder | encrypted | `OinklyBudget.vault` and `.vaultkeys` in the shared folder |

- **Opening** always ends in a private working copy and a lock (a lock only when shared).
- In shared and encrypted mode, check-out **decrypts** into the working copy and check-in **seals** it back, so only ciphertext is ever in the shared folder.
- Every login uses the **same passphrase and recovery key** (they unlock the same vault) but remembers the key in **its own Keychain**.
- The honest limit stays: while the app is open, the working copy is readable in that login's private storage. Encryption protects the shared folder, a copied file and backups. It does not protect a Mac that is unlocked and in use, and does not hide data from another login that has the passphrase.

**Code consequence.** Replace the two sessions with one `DataFileSession` that has a *source* (this Mac or a shared folder) and a *seal* (none or vault). `VaultSession` and `SharedDataSession` become small parts of it. The old ones keep working for the local cases until the new one replaces them, so the existing tested paths are not broken while building.

## 8. The database upgrade (V1 to V2) in shared mode

- Everyone on one Mac runs the **same app**, so version differences only happen during an update. Still: `info.json` records `formatVersion` and `schemaVersion`. An older app opening newer data refuses with a clear message. A newer app opening older shared data upgrades **the working copy** (the V1 to V2 step already exists) and the upgrade reaches the shared file at the next check-in, after the safety copy.
- The first-time 1.0 safety copy (Application Support ▸ Backups ▸ Before this update) still happens for this login's own data. When joining an existing shared file, a copy of it is made first, in the shared folder's `previous saves`.
- Table counts for verification must come from the database's own table list, not a fixed list, so V2's new tables are included automatically.

## 9. What the person sees

**Settings ▸ Data & Backup ▸ Shared Data File** (a new section):

- **Not sharing:** a short explanation and **Share This Data…**, which shows the warning in 12b and then copies this Mac's data into `/Users/Shared/OinklyBudget` (never moves or changes the original).
- **Sharing:** the folder path with Show in Finder, who has the file and since when, last saved time, and the buttons **Save Now**, **Close File So Someone Else Can Use It**, **Open Recent** (a pop-up of folders used before), **Move This File…**, **Create a New Data File…**, **Check Sharing** (a diagnostic, see 11), and **Stop Sharing**.

**At launch**, if someone else has the file, a waiting screen says so and the app opens by itself as soon as the file is free; only a lock that has gone quiet offers **Open Anyway** (D17). If the folder is missing: **Locate…**, **Choose Another…**, **Use This Mac's Own Data**. It never starts an empty database silently.

**While running**: a small status in the bottom bar ("Shared · saved 3:12 PM") and a banner if the lock is taken or a save fails ("Your changes are safe on this Mac and will be tried again").

## 10. Failure handling (what happens when something goes wrong)

| What goes wrong | What happens | Tested by |
|---|---|---|
| Save fails (disk full, folder gone) | Old shared file untouched. Banner. Working copy kept and retried. | D5, new S1 |
| App crashes mid-edit | Marker and working copy remain. Next launch keeps the work (or saves it as a recovered copy if someone else saved meanwhile). | D3 |
| Crash during a save | Temp file ignored; shared file is the old one or the new one, never half. | new S2 |
| Another login takes a stale lock | Original app goes read-only at its next check or on wake. Its unsaved work is kept as a recovered copy. | D3 |
| Mac sleeps with the lock held | On wake, check the lock at once. If still ours, carry on. If taken, as above. | new S3 |
| Folder moved or renamed | Bookmark resolves the move; if not, "folder missing" screen. | new S4 |
| Folder on an unplugged drive | Same as missing. | new S4 |
| Wrong permissions (the other login can't write) | **Check Sharing** says so in plain words at setup, and a failed first save from the second login shows the same message. | Phase 0 |
| File from a newer app | Refused with a clear message. | new S5 |
| Passphrase wrong or key file missing (encrypted) | Same screens as today's vault. Nothing changes. | C1 to C6 |
| Two logins start at once | Exclusive lock create: one wins, the other sees "in use". | new S6 |
| Verify fails (counts or integrity) | Nothing replaced. Message. Working copy kept. | A and D tests |
| Damaged shared file | Open the previous save (one tap) or the previous saves folder. | new S7 |

## 11. The tools to make it safe to trust

- **Check Sharing:** shows the folder's owner and permissions, free space, whether a test file can be created, renamed and deleted by this login, whether the folder is on this Mac's disk, and the last few saves. It's the first thing to run when something doesn't work.
- **Previous saves:** keeps the last few finished files with their time and who saved them (see D8), and a **Restore a Previous Save…** action.
- **Save log:** a small text log in the shared folder (who, when, size, revision) so any odd change can be traced.

## 12. Decisions needed (with options and my recommendation)

| # | Decision | Options | Recommendation |
|---|---|---|---|
| D1 | Can sharing be used **without** encryption? | A) Yes, each is optional. B) Sharing requires encryption. | **A.** Encryption stays opt-in, as promised. Sharing plain data in a folder everyone on the Mac can read is the owner's choice and Help says so. |
| D2 | **Stop Sharing**: what does this Mac's data become? | A) The latest shared data is copied to this Mac (after a safety copy of what was there). B) Go back to this Mac's old data, which may be out of date (the prototype). C) Ask each time. | **A.** B can silently bring back stale data, which is exactly the loss this feature must not cause. |
| D3 | Starting data when sharing is first turned on | A) Copy this Mac's data into the folder (never move). B) Also offer to join a folder that already has data (replaces this login's data after a safety copy). | **Both**, with a clear choice and a safety copy. |
| D4 | ~~Take over a lock that still looks alive~~ | Replaced by D17. | Answered "yes" first; D17 is simpler: only a lock that has gone quiet for 3 minutes can be taken. |
| D5 | ~~Open read-only while someone else has it~~ | Dropped by D17. | The app waits instead. |
| D6 | How often to save back | A) Every 2 minutes if changed (prototype). B) Every 5 minutes. C) After every change. | **A**, then measure on a large file and move to B if saves are slow. C is too heavy. |
| D7 | Heartbeat and stale limit | A) 60 seconds and 3 minutes (prototype). B) 30 seconds and 2 minutes. C) Longer. | **A.** Sleep makes shorter limits trigger false takeovers. |
| D8 | History of finished saves kept in the folder | A) One previous save (prototype). B) The last 5 saves plus one per day for 7 days. C) None. | **B.** Costs disk space (about 6 to 12 copies) but makes any bad save recoverable. Receipts are shared, not copied, between these. |
| D9 | Which settings are shared | A) Per login (currency, appearance, reminders, paper, style). B) Some in the file. | **A.** Preferences are personal. Reminder notifications go to the login that set them. |
| D10 | Folder locations | A) Only this Mac's own disk; block network volumes and warn on cloud-synced folders. B) Allow anything. C) Block cloud folders too. | **A.** The finished file is written whole, so a sync service is less harmful than for a live database, but a synced folder can make "conflicted copies" and the lock would be wrong across Macs. |
| D11 | Open Recent, Move This File, Create a New File | A) All three in 1.0. B) Open Recent only. | **A.** They were on the prototype's list. Move and Create are small once the pipeline is one system. |
| D12 | Receipt clean-up | A) Remove unused ones at a clean close after 30 days. B) Never remove. | **A.** Otherwise the shared folder grows forever. |
| D13 | ~~Ask the other login to let go~~ | Replaced by D17. | Left out of 1.0; it can be added later as a Close It button. |
| D16 | ~~Automatic handoff~~ | Replaced by D17 on the same day. | The owner preferred something simpler and safer. |
| D17 | **When another login has the file open** | A) Stop with a waiting message that re-checks by itself; Open Anyway only when the other copy has gone quiet for 3 minutes. B) Close the other copy automatically. C) The message plus a Close It button. | **A** (chosen by the owner, 2026-10-18; see 12c). |
| D15 | How the shared folder is chosen | A) A fixed folder, `/Users/Shared/OinklyBudget`, made by the app with a narrow sandbox exception, no panel. B) The same folder proposed, with the system panel pointing at it for one click. C) The person chooses any folder. | **A** (chosen by the owner, 2026-10-18; see 12b). B is the fallback if App Review refuses the exception. C is dropped: a person could pick a protected, network or cloud folder. |
| D14 | What if the two-login test fails or finds permission problems | A) Fix and retry. B) Ship 1.0 without sharing and leave it for 1.2. | **Plan for B as the fallback.** Sharing is the last step, so dropping it does not disturb the rest. Decide at the gate after Phase 1. |

### 12a. Answers so far (2026-10-18)

Answered by the owner:

- **D1: Yes.** Sharing works with or without encryption. Help states the difference plainly.
- **D2: The latest shared data.** Stop Sharing copies the latest shared data to this Mac, after a safety copy of what it had.
- **D17 (replaces D4, D5, D13 and D16): stop with a waiting message.** If another login has the data open, the app waits and opens by itself when it is free. Only a lock that has gone quiet for 3 minutes offers Open Anyway. See 12c.
- **D8: Last 5 saves plus one per day for a week**, with Restore a Previous Save.

Everything else is **accepted as recommended** (confirmed by the owner, 2026-10-18): D3 (copy this Mac's data in, and also offer to join an existing folder), D6 (save every 2 minutes if changed, then measure), D7 (60 second heartbeat, 3 minute stale limit), D9 (settings per login), D10 (this Mac's own disk only; block network volumes; warn on cloud-synced folders), D11 (Open Recent, Move This File and Create a New File all in 1.0), D12 (remove unused receipts at a clean close after 30 days), D14 (fall back to shipping 1.0 without sharing if the permissions test fails).

### 12c. When the other login has the file open (decision D17, 2026-10-18)

The owner does not want the app to close anyone else's copy. The rule is simple: **if the other login has the data open, the app waits and says so.** Nothing is closed, nothing is taken, no data can be lost this way.

**What the person sees.** A waiting screen in place of the boot screen's usual progress, with no buttons to decide anything:

> **Oinkly Budget is already open in Sam's session.**
> Your data is open in another user account on this Mac. Quit Oinkly Budget there (switch to that account and press ⌘Q) and this will open by itself.
> *Waiting…*  [Quit]

- It looks at the lock every 2 seconds and opens by itself the moment the other copy lets go.
- **If the other copy has crashed or gone quiet** (its heartbeat is older than 3 minutes), the screen changes: "Sam's copy of Oinkly Budget seems to have stopped. [Open Anyway]". Open Anyway takes the lock. What the other copy had saved is in the shared file (at most 2 minutes old); anything newer stays in its working copy and is kept as a recovered copy if it ever starts again. This is the only way past the screen, so a crash can never lock people out.
- **Quit** just quits; nothing changes.

**Why this and not an automatic close.** No code to ask another login's app to quit, no race between two copies, and no half-filled form lost. The cost: if the other login is switched away with the app still open, the second person has to switch to that account and quit it first. That is a few clicks, and Help explains it.

**What this removes from the plan.** No request file, no 2-second polling of requests, no countdown notice, no forced quit, no read-only mode, no take-over warning screen. What stays: the lock, the heartbeat (needed to tell a crash from a copy that is open), crash recovery and the recovered copy.

**Later, if wanted.** A "Close It" button (an automatic request to the other copy to save and quit) can be added without changing anything else.

### 12b. The fixed shared folder (decision D15, 2026-10-18)

The owner does not want people choosing a folder, because they might pick a protected area. So the shared folder is **always** `/Users/Shared/OinklyBudget`. The app makes it and every login on the Mac uses it.

**How it works with the sandbox.** A sandboxed app can't touch `/Users/Shared` unless the person grants it through the system's panel. Tested on 2026-10-18: with no exception the app is refused ("Operation not permitted"). With a narrow temporary-exception entitlement, `com.apple.security.temporary-exception.files.absolute-path.read-write`, listing exactly two paths, `/Users/Shared/OinklyBudget` (the folder itself) and `/Users/Shared/OinklyBudget/` (everything inside), the app **can create the folder and work inside it with no panel**, and nothing else in `/Users/Shared` is reachable. Each login's sandbox gets the same exception, so the second login needs no panel either.

**The risk.** Apple discourages temporary exceptions in Mac App Store apps and may ask why. Mitigations:
- The exception is as narrow as it can be (one folder).
- The App Review notes explain it: it is the only way for two Mac logins to share one data file, nothing is sent anywhere, and the feature is off until the person turns it on.
- If review refuses it, the app switches to option B: it proposes the same folder and shows the system panel pointing at it, and refuses any other folder. The sharing code doesn't change, only how access to the folder is granted, so this is a small change.

**What the person sees when turning sharing on.** A plain warning before anything is copied:

> **Share your data with other users of this Mac?**
> Oinkly Budget will copy your data into **/Users/Shared/OinklyBudget**. That folder can be opened by every user account on this Mac. Your data stays on this Mac and is never sent anywhere, but anyone who can log in to this Mac can read it **unless you turn on encryption** (Settings ▸ Data & Backup ▸ Encrypt Data). Your original data is not changed or removed.
> [Share] [Encrypt First…] [Cancel]

**Rules that follow from it.**
- The folder is on this Mac's own disk by construction, so network and cloud folders (D10) can't happen.
- The first login to turn sharing on creates the folder with open permissions (777, not sticky). Another login joining finds it ready. If the folder exists but is not open (for example someone made it by hand), Check Sharing says exactly what to change.
- **Move This File** and **Create a New Data File** (D11) now mean choosing another file inside the shared folder, not another place on disk. **Open Recent** lists the data files in the shared folder.

## 13. Order of work, with a stop point

| Phase | Work | Output | Effort |
|---|---|---|---|
| **0. Permissions spike** | Tiny throwaway test: create the folder, write and replace a file as login A, then replace it as login B, with the app's real sandbox. Run by the owner with two logins. | A yes or no on the biggest risk, with the exact folder settings that work. | 1 to 2 days (and a session with the owner) |
| **1. Plain sharing on V2** | Bring the prototype to V2. Exclusive lock. Revision counter. Wake check. Check Sharing. Settings section and launch screens. | Plain shared data works for two logins. | about 1 week |
| **Gate** | Owner runs the full two-login test (section 14). Decide go or fall back (D14). | Go or no go. | 2 days |
| **2. One system with the vault** | `DataFileSession` with the four locations. Encrypted shared mode. Each login's key from its own Keychain. | Encrypted sharing works. | about 1 week |
| **3. The rest** | Open Recent, Move, Create, previous saves and restore, receipt clean-up, save log, large-file timing and tuning. | Feature complete. | about 1 week |
| **4. Hardening** | All shared-file tests from the data integrity plan, crash and large-data tests, then Help, screenshots and release notes. | Release candidate. | about 1 week |

About 4 weeks in all, in line with the plan's estimate. The gate after Phase 1 is deliberate: if the permissions test fails, little was spent.

## 14. The two-login test (the owner does this)

Setup: a second macOS user on the same Mac (System Settings ▸ Users & Groups), and fast user switching on (Control Center ▸ Fast User Switching).

1. Login A: share the data into a new folder (for example one inside `/Users/Shared`). Add a few transactions with receipts.
2. Switch to login B (do not log A out). Open the app. Expected: a waiting screen naming A. Nothing opens and A is unaffected.
2b. In A, quit the app (⌘Q). Expected: B's waiting screen opens by itself within a few seconds, with A's data.
3. Back in A: Close File So Someone Else Can Use It. In B: open it, add a transaction, close. In A: open again and see B's transaction and receipt.
4. Crash test: in A, force quit the app while editing; reopen; the unsaved work is kept.
5. Crashed holder: in A, force quit; in B, open: the waiting screen shows, and after 3 minutes it offers Open Anyway, which works.
6. Unresponsive holder: pause A's app (Activity Monitor) and open B: after 3 minutes B offers Open Anyway; A, when resumed, keeps its work as a recovered copy.
7. Sleep: close the lid with A holding the lock for 5 minutes; open B; take over; wake A.
8. Encrypted (after Phase 2): repeat 1 to 5 with encryption on; confirm the shared folder holds no readable data (`OinklyBudget.vault` only).
9. Large file: a data set of about 20,000 transactions; time the saves.
10. Permissions: confirm B can replace A's file and that nothing needs `sudo`.

## 15. Tests this adds to the data integrity plan

Section D (D1 to D6) stays. New: S1 save fails (disk full), S2 crash during a save, S3 sleep and wake, S4 folder moved or drive unplugged, S5 newer-format file, S6 simultaneous start, S7 restoring a previous save, S8 stop sharing leaves this Mac with the latest data, S9 joining an existing folder, S10 encrypted sharing leaves only ciphertext in the folder.

## 16. What changes in the plan documents when this is built

Help (a new topic: Sharing One Data File, with the two-login setup, the permissions notes and the honest limits), screenshots S-F4a to S-F4d, the website security and privacy text, release notes (a headline feature, with "one at a time" stated plainly), the data integrity plan record, and the App Review notes (still no network).

## 17. Phase 1 status (2026-10-21)

**Built (plain sharing on V2):** the fixed folder `/Users/Shared/OinklyBudget` made open to every user; `SharedDataFolder` (finished file, `info.json` with revision, schema version and file ID, exclusive `lock.json`, one previous save, recovered copies, Check Sharing report); `SharedDataSession` (check out and check in with checks, marker and crash recovery, heartbeat every 60 seconds, wake-from-sleep check, saves every 2 minutes while changed, on hide and on quit, Stop Sharing); the waiting screen (D17) with Open Anyway for a copy quiet for 3 minutes; a Shared Data File section in Settings ▸ Data & Backup with the warning text, Save Now, Close for Others, Check Sharing and Stop Sharing; Erase All Data and Turn On encryption are switched off while sharing.

**Tested on one Mac login with the debug build:**
- Turning sharing on creates the folder (mode 777), the data file, `info.json` and the lock; the app opens the shared data and the numbers match.
- Quit saves, increments the revision, keeps one previous save and removes the lock.
- A fresh lock held by another user shows the waiting screen; removing the lock opens the app by itself within a few seconds.
- A lock quiet for 10 minutes shows "seems to have stopped" and Open Anyway takes it.
- A force-quit (kill -9) leaves the lock; the next start takes over the same user's dead lock and shows "closed unexpectedly, your unsaved changes were kept".
- Another login taking the lock while this copy runs: this copy shows the "someone else is using the shared data" notice within a minute, leaves the shared data alone, keeps its own copy as a separate "recovered" file on quit and does not remove the other login's lock.
- Joining a folder that already has data keeps this Mac's own data untouched.
- Stop Sharing keeps a safety copy of this Mac's data in Backups, copies the latest shared data to this Mac and releases the lock.
- Check Sharing reports owner, permissions, disk, create/rename/delete rights, last save and who has it.

**A bug found and fixed on the way:** after a force-quit, macOS reopens the main window from the last session. With the waiting screen active that window showed an empty app that could have been added to. The main window now shows the waiting screen itself in that state, so an empty database can never be shown.

**Not yet tested:** a real second login (the gate), waking from sleep, two copies starting in the same instant, a large data file, encryption with sharing (Phase 2), and App Review's view of the folder exception.

## 18. Phase 1 gate test (the owner and a second login)

Use the steps in section 14, with these specifics:
1. Build or copy the app to `/Users/Shared/OinklyBudget-TestApp/OinklyBudget.app`. Both logins run that copy.
2. Login 1: Settings ▸ Data & Backup ▸ **Share…**, read the warning, **Share**. Add a transaction and a receipt photo.
3. Switch to login 2 (do not log 1 out). Open the app. It should show **"Oinkly Budget is already open in … session"** and wait. Nothing else on screen can be used.
4. In login 1 press ⌘Q. Login 2's waiting screen should open the app by itself in a few seconds, with login 1's transaction and receipt.
5. In login 2, add a transaction, then ⌘Q. In login 1, open the app and see it.
6. Crash: in login 1 force quit the app (Activity Monitor ▸ Force Quit). In login 2, open the app: it shows the waiting screen, then after 3 minutes **Open Anyway**. Use it. Login 1 then opens its app again: it should say the shared data was taken and keep its own copy.
7. In Settings ▸ **Check Sharing…** in each login: every line should say OK.
8. Each login: **Stop Sharing** at the end if you want to go back.
