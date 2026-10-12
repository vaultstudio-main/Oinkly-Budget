# Piggybank Financial 1.0: Mac release plan

Status as of 2026-10-11. Piggybank is a **Mac-only** app. The iPhone and iPad code was removed (still in git history up to
`aa90b3f`), and there is no sync: data lives on the Mac, and `.pig` backups are the way to move or protect it.

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
- [ ] **Price.** Free, paid, or free with a tip? Decide before creating the app record.
- [ ] **Minimum macOS.** The project currently requires macOS 27.0 (`MACOSX_DEPLOYMENT_TARGET`). Lower it if you want to
      reach people on older systems, then build and test on that version.
- [ ] **Name.** The app is "Piggybank Financial" (bundle id `vault.Piggybank`). Check the name is free in App Store Connect.
- [ ] **Support and privacy URLs.** App Store Connect requires both. A one-page site or a GitHub page is enough.
      Privacy statement in one line: nothing is collected, nothing leaves the Mac.

### 2. Accounts and signing (you)
- [ ] Paid Apple Developer Program membership (the project already has team `LVKJ422Q3M`; confirm it is the paid one).
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
container). Tick each:
- [ ] First launch: boot window, then the account setup screen. Add a checking account, a card and a loan.
- [ ] New Transaction, Cash Transaction, Credit Card Charge, ATM Withdrawal, Transfer, Pay a Bill. Balances move.
- [ ] Edit and delete a transaction. Delete one half of a transfer (both go).
- [ ] Add a receipt photo and a PDF. Remove one.
- [ ] Add a bill, mark it paid, pay it with Pay a Bill. Reminder permission prompt appears the first time.
- [ ] Notifications: Settings ▸ General ▸ Send a Test Notification shows a banner.
- [ ] Goals: create, add progress, reach one (it archives).
- [ ] Reports: all four tabs, back and forward, Current pill.
- [ ] Backup: Export Backup, Erase All Data, open the `.pig` (double-click) and confirm everything returns.
- [ ] Light and dark appearance, a resized window, full screen.
- [ ] Quit with ⌘Q, reopen: data is there. Close the window: menu bar item stays.
- [ ] Update test: install this build over the previous dev build and confirm your data opens.

### 5. Store listing (you)
- [ ] Name, subtitle, description, keywords, promotional text. Mention Mac only.
- [ ] Screenshots: Mac App Store takes 1280×800, 1440×900, 2560×1600 or 2880×1800. The Help screenshots in
      `Piggybank/Assets.xcassets/Help-*.imageset` are the right content (Summary, register, bills, reports, goals) but
      are small. Retake them at full size on your Mac in light mode with sample data (Testing ▸ Fill with Test Data),
      using `docs/help-screenshots.md` as the shot list.
- [ ] Age rating questionnaire (no objectionable content).
- [ ] App Privacy answers: "Data Not Collected".
- [ ] Review notes: no account needed; to look around, use Piggybank ▸ Testing is NOT in release builds, so mention that
      the reviewer can add accounts from the setup screen.
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
- The ATM Withdrawal and Pay a Bill windows have empty space below the form.
- Debug builds are much slower than Release, especially under Xcode's debugger. Judge speed on Release only.
- Reports (yearly) loads the whole year, about 1.5 s at 100,000 transactions. It could read from the ledger snapshot.
- After an edit the Summary can be a second behind while the background snapshot rebuilds. Registers are exact.
- Importing a very large CSV into an account that already has tens of thousands of rows is slow (SwiftData cost).
- No sync between devices (decided), and no mobile version. See `docs/icloud-sync-plan.md` for the companion-app idea.

## After release
- Take a `.pig` backup before every update you install on your own Mac.
- Any change to a stored model property needs `PiggybankSchemaV2` and a migration stage before it ships.
- Keep `checkpoint` pointing at the last build you shipped.
