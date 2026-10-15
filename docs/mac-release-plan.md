# Piggybank Financial Budget 1.0: Mac release plan

Status as of 2026-10-11. Piggybank is a **Mac-only** app. The iPhone and iPad code was removed (still in git history up to
`aa90b3f`), and there is no sync: data lives on the Mac, and `.pig` backups are the way to move or protect it.

> Repository layout: this folder is the git repository. The Mac app is in `Piggybank/` (its Xcode project and source),
> these notes are in `docs/`, and a `piggybank-windows/` folder can sit beside them later. File paths below that
> start with `Piggybank/` are inside that app folder.

## Where the app stands
- Features for 1.0 are in: accounts of every kind, registers, receipts, bills and reminders, goals, budgets, reports,
  investments, liabilities, backups, menu bar item, notifications, Help with 18 screenshots, Release Notes.
- Measured at 100,000 transactions (Release build): every page opens in 1.5 s or less. See the speed notes in
  `git log` (`82b30e1`). Typical households will never get near that.
- Code is cleaned up (dead code removed) and `checkpoint` marks a known-good commit.
- The database is versioned (`PiggybankSchemaV1`, `Models/SchemaVersions.swift`), so a future update can migrate it.

## Before you submit
Work top to bottom. Items marked **you** need your account, your Mac or your eyes.

### 1. Product decisions (you)
- [x] **Price: $9.99** (one-time purchase). Needs, in App Store Connect before you can sell:
      the **Paid Apps Agreement** signed, **banking** details and **tax** forms completed (Business ▸ Agreements, Tax and
      Banking). **Done.** The **App Store Small Business Program** application is **submitted** (Apple's commission drops
      from 30% to 15% while your yearly proceeds are under $1 million); wait for Apple's approval. There are no free trials on the Mac App Store, so the screenshots and
      description have to do the selling. Promo codes can be given to reviewers or friends.
- [x] **Minimum macOS** is now 15.0 (`MACOSX_DEPLOYMENT_TARGET`). It builds clean, but only macOS 27 was available to test
      on: run it once on a Mac with macOS 15 or 26 if you can. 14 is not possible without reworking how windows open
      (`defaultLaunchBehavior` and `restorationBehavior` need macOS 15).
- [x] **Name.** "Piggybank Financial" was already taken in App Store Connect, so the name everywhere (store, app, website)
      is **Piggybank Financial Budget** (bundle id `vault.Piggybank`).
- [x] **Website is live** at https://vaultstudio.dev (source in `docs/website`, see its `README.md`) and the support
      address `support@vaultstudio.dev` is set up. Use these in App Store Connect: Support URL
      `https://vaultstudio.dev/support`, Privacy Policy URL `https://vaultstudio.dev/privacy`, Marketing URL
      `https://vaultstudio.dev/piggybank`. (The host serves clean addresses without `.html`.) Still to do on the site
      later: swap the "Coming soon" button for the App Store link when the app is live.

### 2. Accounts and signing (you)
- [x] Paid Apple Developer Program membership (confirmed; the project uses team `LVKJ422Q3M`).
- [ ] App Store Connect: create the app record, platform **macOS**, bundle id `vault.Piggybank`, category Finance.
- [ ] Signing: Automatic, Apple Distribution certificate, Mac App Store provisioning. Xcode handles it on Archive.
- [ ] Sandbox entitlements the app needs: App Sandbox, User Selected File (read/write). Nothing else. Notifications need
      no entitlement. `Piggybank/Piggybank.entitlements` is not wired into the target; leave it unwired (it lists iCloud and
      push keys that are not used) or delete it.

### 3. Already done in the project
- [x] Hardened runtime and sandbox on.
- [x] `PrivacyInfo.xcprivacy` (no tracking, no data collected, UserDefaults reason CA92.1).
- [x] `ITSAppUsesNonExemptEncryption = NO` (no export-compliance question on upload).
- [x] App icon in the boot-splash gradient, all sizes.
- [x] Help screenshots and Release Notes hero image.
- [x] Versioned database schema.
- [x] Debug-only tools (Testing window, test data, stress load) are behind `#if DEBUG`.

### 4. Build quality pass (you, about an hour)
Run the **Release** build, not Debug, from a fresh store (Settings ▸ Data ▸ Erase All Data, or delete the app's
container). Tick each. **All done (confirmed by you, 2026-10-14), along with a backup of your real data.**
- [x] First launch: boot window, then the account setup screen. Add a checking account, a card and a loan.
- [x] New Transaction, Cash Transaction, Credit Card Charge, ATM Withdrawal, Transfer, Pay a Bill. Balances move.
- [x] Edit and delete a transaction. Delete one half of a transfer (both go).
- [x] Add a receipt photo and a PDF. Remove one.
- [x] Add a bill, mark it paid, pay it with Pay a Bill. Reminder permission prompt appears the first time.
- [x] Notifications: Settings ▸ Reminders ▸ Send a Test Notification shows a banner.
- [x] Goals: create, add progress, reach one (it archives).
- [x] Reports: all four tabs, back and forward, Current pill.
- [x] Backup: Export Backup, Erase All Data, open the `.pig` (double-click) and confirm everything returns.
- [x] Light and dark appearance, a resized window, full screen.
- [x] Quit with ⌘Q, reopen: data is there. Close the window: menu bar item stays.
- [x] Update test: install this build over the previous dev build and confirm your data opens.

### 5. Store listing (you)
- [ ] Name, subtitle, description, keywords, promotional text. Mention Mac only. A full draft is in
      `docs/app-store-listing.md`; paste each block in (the domain and studio name are already filled in).
- [x] Screenshots: 10 at 2880×1800 (dark mode, sample data, no alpha) are in `docs/app-store-screenshots`. Lead with
      01-summary, 06-bills, 08-checking, 03-reports, 05-investments. Upload up to 10.
- [ ] Age rating questionnaire (no objectionable content).
- [ ] App Privacy answers: "Data Not Collected".
- [ ] Review notes: no sign-in needed. The reviewer adds a few accounts from the setup screen to look around. (The
      Testing window and test data exist only in Debug builds, so there is no demo data to offer in a release build.)
- [ ] What's new (1.0): copy from the Release Notes window.

### 6. Archive and upload
1. Set version `1.0`, build `1` (target ▸ General). Bump the build number for every upload.
2. Product ▸ Archive (scheme Piggybank, destination My Mac).
3. Organizer ▸ Validate App, then Distribute App ▸ App Store Connect ▸ Upload.
4. In App Store Connect: pick the build, add it to the version, submit for review.
5. TestFlight (Mac) first if you want a few people to try it. Add them as internal testers.

### Alternative: direct download (no App Store)
Archive ▸ Distribute App ▸ Developer ID ▸ Upload for notarization ▸ export the notarized app ▸ put it in a DMG. No review,
no 30% cut, but you host it and handle updates yourself. The sandbox can stay on.

## Known rough edges (none block a 1.0)
- Debug builds are much slower than Release, especially under Xcode's debugger. Judge speed on Release only.
- Reports (yearly) loads the whole year, about 1.5 s at 100,000 transactions. It could read from the ledger snapshot.
- After an edit the Summary can be a second behind while the background snapshot rebuilds. Registers are exact.
- Importing a very large CSV into an account that already has tens of thousands of rows is slow (SwiftData cost).
- No sync between devices (decided), and no mobile version. Backups (`.pig`) are how data moves between computers.

## After release
- Take a `.pig` backup before every update you install on your own Mac.
- Any change to a stored model property needs `PiggybankSchemaV2` and a migration stage before it ships.
- Keep `checkpoint` pointing at the last build you shipped.

## After 1.0
- A Windows version is planned: see `piggybank-windows/PLAN.md`.
