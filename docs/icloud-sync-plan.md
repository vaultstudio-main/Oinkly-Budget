# iCloud sync: plan for later

Status: **not started.** Decided to finish the feature list first.

## Where things stand
- The app uses a plain local SwiftData store (`ModelContainer(for: schema)` in `Piggybank/PiggybankApp.swift`).
- `Piggybank.entitlements` lists CloudKit but has an empty `icloud-container-identifiers`, so nothing syncs.
- Each device (Mac, iPhone, iPad) holds its own data. `.pig` backups (Mac Settings ▸ Import / Export) are the only way to move data.
- Help, About and the Data settings all say data never leaves the device. These need rewording if sync ships.

## Steps
1. **Prerequisites**
   - Paid Apple Developer account.
   - Create an iCloud container (for example `iCloud.vault.Piggybank`).
   - Turn on the iCloud (CloudKit) capability for macOS and iOS, and add the container to the entitlements.
   - Remove the unused `aps-environment` entry duplicates if Xcode flags them.
2. **Schema review against CloudKit rules** (do this before touching the store)
   - Every attribute optional or defaulted. Every relationship optional. No unique constraints.
   - Models to check: Account, Category, Transaction, Payee, Holding, HoldingEvent, Bill, Goal, GoalContribution, CustomPaymentMethod.
   - Raw-value enums stay as they are. Never rename cases.
   - `@Attribute(.externalStorage)` fields (account, bill and receipt photos) are allowed, but check size limits.
3. **Duplicates**
   - Categories are seeded on every launch and merged by `systemKey` (`Category.ensureSystemCategories`). Two devices seeding before their first sync will create duplicates. The existing merge pass should cope, but test it.
   - Transfers pair two transactions by `transferID`. Confirm both halves always arrive and `StartupChecker` doesn't "release" one half as broken mid-sync.
4. **Turn it on**
   - Use `ModelConfiguration(cloudKitDatabase: .private("<container id>"))`.
   - Keep an in-memory fallback on failure, as now.
5. **Migrating existing data**
   - Prompt for a `.pig` export before the first sync-enabled launch.
   - Decide whether sync is opt-in (a Settings toggle) or always on. Opt-in is safer for the "local only" promise.
6. **User-facing text**
   - Update Help, About, release notes and Settings ▸ Data copy.
   - Show sync status somewhere simple (last synced, or an error).
7. **Things the sync design must handle**
   - Notifications and the menu bar item read local data only, which is fine.
   - Deleting data (Erase All) must be clear that it erases on every device.
   - Restoring a `.pig` backup replaces data everywhere.

## Test plan
- Two simulators and the Mac against one iCloud account.
- Add, edit and delete on each. Check transfers, bill payments, goals and photos.
- Offline edits that conflict.
- A fresh device joining an account that already has data (watch for duplicate categories).

## Readiness audit (2026-10)
Checked against the current code. Items 1 and 4 are done; 2 and 3 are the next steps (numbering matches the original audit).

**Done (2026-10)**
- [x] Declared defaults added to every non-optional attribute (Account, Category, Transaction, Payee, Holding, HoldingEvent).
- [x] The database is opened with `cloudKitDatabase: .none` explicitly, so adding a container can't start syncing by accident. Same store file as before.

**Still to do, in this order**
2. **Wire the entitlements into the project.**
   - `Piggybank.entitlements` exists but `CODE_SIGN_ENTITLEMENTS` is unset, so the built Mac app only carries sandbox + user-selected-files.
   - Set `CODE_SIGN_ENTITLEMENTS` for the app (both platforms, or one file per platform if they differ).
   - Clean the file: `aps-environment` is listed twice (`aps-environment` and `com.apple.developer.aps-environment`). Keep the one Xcode expects, and fill in `icloud-container-identifiers`.
   - Check the built app with `codesign -d --entitlements -` on the Mac build to confirm the iCloud keys are really there.
3. **Create the iCloud container and enable the capability.**
   - Needs the Apple Developer account (a team is already set on the project: check it is a paid one).
   - Create the container (for example `iCloud.vault.Piggybank`) in the developer portal.
   - Add the iCloud capability with CloudKit to the macOS and iOS targets in Xcode, pick that container, and add Push Notifications.
   - Then, and only then, switch the database in `PiggybankApp.swift` from `.none` to `.private("<container id>")`.

**Fine already**
- No unique constraints and no `.deny` delete rules.
- To-one relationships are optional; to-many default to `[]`.
- Photos, receipts and PDFs use `.externalStorage` (becomes CKAsset).
- iOS has the `remote-notification` background mode.
- Raw-value enums and `[Date]` arrays are storable.

**Needs a decision or a test**
- Duplicate seeding: built-in categories are created per device. The existing merge by `systemKey` should handle it, but test a second device joining.
- Payees can duplicate by name across devices.
- `StartupChecker` "releases" a transfer that has only one half. Mid-sync that could wrongly break a real transfer, so hold it back until sync has settled.
- Preferences (currency, appearance, reminders) are device-local. Decide whether to sync them (key-value store) or leave them.
- Erase All Data and restoring a .pig will propagate to every device.
- iOS falls back to `fatalError` if the container can't be created; give it a graceful path before enabling sync.
- Verify `Decimal` and the `ClearedStatus`/`PaymentType`/`AccountType` enums round-trip through CloudKit on a real device.
- Mac sandbox: confirm whether CloudKit needs the outgoing-network entitlement (currently off).
- Migration: take a .pig backup and prompt before first sync-enabled launch.
