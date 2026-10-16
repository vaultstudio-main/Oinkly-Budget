# OinklyBudget for iPhone and iPad — plan

Drafted 2026-10-15, decisions made the same day. Nothing here is started. The Mac release comes first.

## Decisions (made)

1. **iCloud sync ships with the first iOS release.** Mac, iPhone and iPad stay in step.
2. **$9.99, one purchase for all of them** (Universal Purchase).
3. **iPhone and iPad together** from day one.
4. **Widgets and Face ID lock are in the first release.**
5. **The Windows version is dropped.** iOS is the only other platform. The `piggybank-windows/` plan is retired.

## Product direction (updated)

- **The Mac app is the product.** The goal is a full, big, Quicken-style desktop program. Most new features go there first and keep going there through the 1.x releases.
- **The iPhone and iPad app is a companion and viewer.** It is deliberately stripped down. It does not need to list every account or offer every screen. It shows what is useful on the go (balances that matter, bills due, budget left, recent transactions, goals) and may allow quick entry. The full data still syncs to the device, but the app only shows part of it.
- **Family sharing of the data** is a planned feature. It changes how data is saved and shared, so it drives the 2.0 storage rework (see the next section).

Effect on this plan: the iOS app is much smaller than the earlier phases assumed. Most of the effort moves into the Mac features and the storage layer, and the phone UI shrinks to a handful of screens.

## Family sharing and the storage rework (the big one)

Two different things are called sharing, and only one needs the rework:

| Thing | What it is | Work |
|---|---|---|
| **App purchase sharing** (Apple Family Sharing) | Family members can download the app on their own devices. | A checkbox in App Store Connect. No code. |
| **Data sharing** | A household shares one set of accounts, each person on their own Apple ID. | Needs CloudKit sharing. This is the rework. |

Why it matters: SwiftData with CloudKit syncs only to the user's own private iCloud database, and as far as I know it cannot take part in CloudKit shared databases. Data sharing between Apple IDs therefore cannot be added on top of the current storage. Verify this against the current SDK when work starts, since Apple may have changed it.

Options for 2.0:

| Option | Sharing | Notes |
|---|---|---|
| **A. SwiftData + CloudKit private database** | No | Simplest. Syncs a person's own devices only. Fine for iCloud sync alone, but a dead end for family sharing. |
| **B. Core Data with `NSPersistentCloudKitContainer`** | Yes (shared store, `CKShare`) | Mature and supported. Means moving off SwiftData, rewriting the model layer and every `@Query`. |
| **C. Own sync layer using `CKSyncEngine`** | Yes (private and shared databases) | Most control and most work. Keep a local store (SwiftData, SQLite or similar) and sync records yourself. Fits a "full Quicken" app that needs precise conflict handling. |
| **D. A document-style data file in iCloud Drive** | Limited | Matches the existing `.pig` idea. Weak at concurrent edits from several people. Not recommended for a household sharing live data. |

Recommendation: decide between B and C before building any iOS UI, because everything else depends on it. Do not do A, since the family sharing goal makes it a dead end. If the data is reworked anyway, this is also the time to review the model: IDs, change tracking per record, deletion handling, and how multiple people's edits merge.

Questions the sharing design must answer:

- Who owns the shared data set, and who can edit versus only view?
- Is it one shared set of everything, or can individual accounts be shared and others kept private?
- What happens when two people edit the same transaction, or one deletes it while another edits it?
- How does a person leave a share, and what do they keep?
- How does the `.pig` backup behave with shared data?
- Privacy wording: data goes through the users' own iCloud, never to Vault Studio. The privacy page and App Store privacy answers change with 2.0.

Because this is a major change to saving, treat 2.0 as a new major version of the program, possibly with a reworked data layer, and give it its own plan once the options are tested with a small prototype.

## Release sequence

The Mac app gets better through the 1.x releases, and the iPhone and iPad app arrives with 2.0. The iOS groundwork is built quietly inside 1.x so 2.0 is not a rewrite.

| Release | Contents |
|---|---|
| **1.0 (Mac)** | The app as it is now. Local storage, no sync. Ships Friday if review and plans go through. |
| **1.x (Mac)** | Grow the Mac app toward a full Quicken-style program:  printing reports, printing transactions, Save as PDF, printing to paper, and whatever else comes up. iOS scaffolding goes in alongside, with no visible change for users (see below). |
| **2.0 (Mac, iPhone, iPad)** | Reworked data layer, iCloud sync, family data sharing (if the prototype holds up), and the iPhone and iPad companion app with widgets and Face ID lock. Mac and iOS go out together. $9.99 covers all of them. |

### Scaffolding that is safe to add during 1.x

Only changes that do not alter the stored data and are invisible to users:

- **Platform wrappers.** A `PlatformImage` alias for `NSImage` and `UIImage`, and small wrappers for pasteboard, open-URL and file import and export, so shared files stop calling AppKit directly.
- **Printing and PDF built to be shared.** Build the report and transaction printing on SwiftUI views rendered with `ImageRenderer` into PDF pages, with only the last step platform-specific (`NSPrintOperation` on the Mac, `UIPrintInteractionController` and the share sheet on iOS). Then the same report layouts print on the phone in 2.0 for free.
- **Move code into shared folders.** Keep `Models/` and `Logic/` free of AppKit, and keep Mac-only code in the Mac views, so the iOS target can compile them later.
- **Separate view logic from window logic.** Pull the content of each window (Transfer, Bill Pay, New Transaction) into plain views that take a model and a dismiss closure, so 2.0 can show them as sheets.
- **A multiplatform target** can be added once the Mac code compiles cleanly, but is not shipped until 2.0.
- Unit tests for `Logic/` keep running on both.

### The one step that must stay deliberate: the data model

Changing the stored models for CloudKit is not scaffolding, because it changes every user's database. Keep it as a single, tested step (`PiggybankSchemaV2`) done when the sync work starts, not slipped in with feature releases.

- Do not change the models in 1.x unless a feature needs it. If printing or reports need a new stored field, add it in a way that already follows the sync rules (a default value, optional relationships, no unique attributes) so it does not make the 2.0 migration bigger.
- Check the sync-readiness of the current models: no `@Attribute(.unique)` fields and every relationship has an inverse. The to-many relationships (`transactions`, `bills`, `goals`, `holdings`, `events`, `contributions`, `payees`, `loanBills`, `payments`) must become optional for CloudKit and every other stored property needs a default. Photo and receipt data already use external storage, which CloudKit handles as assets.
- Keep `PiggybankSchemaV1` exactly as shipped until the migration is written, so the move has a clean starting point.
- Keep the `.pig` backup prominent. It is the safety net for the move to sync, and Help should tell users to back up before updating to 2.0.
- Nothing about sync appears in the listing, website or privacy page until 2.0.
- Set up the iCloud container and the iOS app record (same bundle ID, for Universal Purchase) in App Store Connect while 1.0 is in review or soon after.

## Goal

Bring OinklyBudget to iPhone and iPad as one universal app that keeps the same promises as the Mac app:

- No bank linking. You enter and check your own numbers.
- Your data stays on your device unless you choose to move it.
- One-time purchase, no subscription, no ads, no tracking.

## The good news: most of the app already travels

The app is SwiftUI and SwiftData, and the logic layer does not depend on the Mac.

| Layer | Files | iOS effort |
|---|---|---|
| Models (`Models/`) | Account, Transaction, Bill, Goal, Holding, Category and so on | None. Shared as is. |
| Logic (`Logic/`) | Budget, Bills, Reports, Investments, Liabilities, backup, CSV | Small. A few files touch AppKit (see below). |
| Views (`Views/`) | About 50 files, built around windows, menus and a menu bar item | Real work. Navigation and layout need a phone and tablet design. |

Roughly 14,600 lines of Swift in total. The models and logic are about half of it and should move almost untouched.

## What is Mac-only today and needs a replacement

These pieces use AppKit or Mac-only scene types. Each one needs an iOS equivalent or a guard.

| Mac feature | Where | On iPhone and iPad |
|---|---|---|
| Multiple windows (`WindowGroup(for:)`, `openWindow`) for New Transaction, Transfer, Bill Pay, ATM, detail | `PiggybankApp.swift`, `MenuCommands.swift` | Sheets and pushed screens instead of windows. |
| Menu bar item with upcoming bills | `MenuBarBills.swift` | Replace with a Home Screen widget and a Lock Screen widget. |
| Menu trimming, key monitor, File and Edit menu commands | `MenuTrimmer.swift`, `MenuCommands.swift` | Not needed. iPad keyboard shortcuts via `.keyboardShortcut` are a nice extra. |
| Settings scene (`Settings { }`) | `PiggybankApp.swift`, `Settings/` | A Settings screen inside the app, or the system Settings app for a few switches. |
| `NSOpenPanel` and `NSSavePanel` for backup, restore, CSV | `DataBackup.swift`, `ImportExportSettingsView.swift` | `fileImporter`, `fileExporter`, and a share sheet. |
| `NSImage`, `NSPasteboard`, `NSWorkspace` | Receipts, account photos, About, Help | `UIImage`, `UIPasteboard`, `openURL`. A small `PlatformImage` typealias covers most of it. |
| Maximize-on-open, boot window, hidden title bar | `MaximizeOnOpen.swift`, `BootView.swift` | Show the startup checks as a launch screen or a first screen, not a window. |
| Hover and right-click context menus, double-click to open | `RegisterView.swift`, `TransactionsView.swift` | Tap to open, swipe actions, long-press context menus. |
| Dense tables (register, reports) | `RegisterView.swift`, `ReportsView.swift` | Lists on iPhone; keep tables on iPad (regular width). |

The reminders code (`CustomReminders.swift`, `BillNotifier.swift`) uses `UNUserNotificationCenter`, which works on iOS unchanged. Notifications are actually more at home on a phone.

## Recommended approach

**One multiplatform SwiftUI app, shared code, separate root views.**

1. Add an iOS destination to the existing Xcode target, or add a second target in the same project, and keep one set of `Models/` and `Logic/` files for both.
2. Keep `MacRootView` and the window scenes behind `#if os(macOS)`.
3. Build a new `PhoneRootView` and `PadRootView`, or one adaptive root that switches on size class:
   - **iPhone:** a `TabView` with Home, Accounts, Bills, Budget and More. Everything else pushes onto a `NavigationStack`.
   - **iPad:** the same `NavigationSplitView` layout the Mac uses (sidebar, list, detail), which is close to what exists now.
4. Reuse the existing detail and editor views where they are already plain forms. The editors (`EditTransactionSheet`, `AccountEditView`, `BudgetEditView`) should mostly work as sheets with small layout changes.
5. Move the Mac-only calls behind small wrappers so the shared files compile on both platforms.

Why this over a separate app: one data model, one set of bug fixes, one `.pig` backup format, and Universal Purchase makes it a single App Store listing if you want it.

## Data and sync (the big decision)

The Mac app stores data locally and has `cloudKitDatabase: .none`. A phone app raises an obvious question: how does the data get from the Mac to the phone?

| Option | What the user gets | Cost and risk |
|---|---|---|
| **A. Standalone, manual transfer** | Each device has its own data. Move data with the existing `.pig` backup and AirDrop or Files. | Least work. Matches the privacy promise. Annoying for people who want both devices current. |
| **B. iCloud sync (CloudKit via SwiftData)** | Mac, iPhone and iPad stay in step automatically. | Most requested feature, most work. Models need CloudKit rules (no unique constraints, optional or defaulted properties, no ordered relationships). Needs testing on real accounts. Changes the privacy wording. |
| **C. iCloud Drive file** | A single backup file kept in iCloud Drive, restored on demand. | Middle ground. Simple, but not real sync and risks overwrites. |

**Decision: B, iCloud sync (CloudKit through SwiftData), in the first iOS release.** The `.pig` backup stays as the manual backup and restore path, and is also how existing Mac data can be moved if sync is not wanted.

This means the Mac app has to change too: it currently runs with `cloudKitDatabase: .none`, so the model rules below must be applied and the Mac release should be updated at the same time as iOS ships. Because sync touches the store, do the model changes as a schema version bump with a tested migration, and test them against a copy of real data before anyone's store is touched.

Things to decide in the work: whether sync is on by default or opt-in in Settings (opt-in fits the privacy message), and how the privacy page, App Store privacy answers and Help describe it (data goes to the user's own iCloud, never to Vault Studio).

Checks before turning sync on:

- Every model property has a default or is optional.
- No `@Attribute(.unique)` fields.
- Relationships are all optional with explicit inverses.
- A schema version bump and a migration path from the current V1 store.
- A test with two real devices, including conflict cases (edit the same transaction on both).

## Phone-specific design notes

- **Fast entry is the whole point.** On a phone people want to add a transaction in a few taps: amount, payee, category, done. Design the New Transaction screen for one hand, with recent payees and the last-used account preselected (`PayeeMemory` already supports this).
- **Home screen.** Keep the "at a glance" idea (`GlanceCards`, `SummaryView`): balance, next bills due, budget left this month.
- **Widgets.** Next bill due and budget remaining are natural first widgets. They replace the Mac menu bar item.
- **Receipts.** The camera and photo picker are better on iPhone than on the Mac. Receipt capture could be a real selling point.
- **Face ID.** Optional app lock for a finance app is expected on a phone. Cheap to add with `LocalAuthentication`.
- **Dynamic Type, Dark Mode, VoiceOver.** App Store reviewers and users on iOS expect these. Check every screen.
- **Landscape and Split View on iPad.** Test at all supported sizes.

## Phases

| Phase | Work | Rough effort |
|---|---|---|
| 0. Prepare | Mostly done during 1.x as scaffolding. Add the iOS destination, get Models and Logic compiling on iOS, wrap AppKit calls. | 2 to 4 days |
| 0b. Sync-ready models | Apply the CloudKit model rules, schema version bump and migration, iCloud capability, two-device test on Mac. | 1 to 2 weeks |
| 1. Skeleton | Phone tab layout, iPad split view, account list, register list, transaction detail, add and edit transaction. | 1 to 2 weeks |
| 2. Core flows | Bills and bill pay, transfers, categories, budget screen, goals, reminders, settings. | 1 to 2 weeks |
| 3. The rest | Investments, liabilities, reports, receipts, `.pig` backup and restore, CSV import and export, Help and About. | 1 to 2 weeks |
| 4. Phone extras | Widgets (next bill, budget left), Face ID lock, haptics. Shortcuts and Spotlight optional. | 3 to 5 days |
| 5. Polish and release | Accessibility pass, iPad multitasking, screenshots, TestFlight, App Store submission. | 1 to 2 weeks |

Estimate for one developer part-time: about 8 to 12 weeks to a first TestFlight build. Phase 1 is where the risk is; do a thin vertical slice first and judge it before committing to the rest.

## Release and App Store

- **Universal Purchase.** Use the same bundle ID family and the same App Store Connect app record so one purchase covers Mac, iPhone and iPad. The Mac app is currently `dev.vaultstudio.oinklybudget`; adding iOS to the same record needs the same bundle ID (check this before the Mac app is final, because changing bundle IDs later is painful).
- **Price.** $9.99, one purchase for Mac, iPhone and iPad (Universal Purchase). Anyone who already bought the Mac app gets iOS free.
- **Minimum iOS.** Match what the code needs. The Mac app targets macOS 15, which lines up with iOS 18. Targeting iOS 18 keeps the code simple; check what share of users that excludes before deciding.
- **Screenshots.** Required sizes are a 6.9" iPhone and a 13" iPad set. Reuse the screenshot pipeline from the Mac release with the Simulator and `xcrun simctl io booted screenshot`.
- **Privacy labels.** Same answers as the Mac app as long as there is no sync and no analytics. Re-check if you add iCloud.
- **Website.** Add iPhone and iPad to the product page and the "coming soon" notes, and update `support.html` and `privacy.html` if data handling changes.
- **Review risks.** Finance apps get extra attention. Keep the "no bank linking, no accounts, your data stays on your device" language clear in the description and review notes.

## Testing

- Reuse the unit tests for `Logic/` unchanged on iOS.
- Test the `.pig` round trip: export on Mac, import on iPhone, export again, import on Mac.
- Run on at least one small iPhone, one large iPhone, and an iPad in portrait and landscape.
- Test with a large dataset (the `TestData` generator already exists) for scrolling and launch time on a real phone.

## Risks

- **Scope.** The Mac UI is built around windows. Treat the phone UI as new design work, not a port.
- **Two code paths.** `#if os(macOS)` sprinkled everywhere gets hard to maintain. Keep the platform differences in a small number of wrapper files.
- **Bundle ID and record.** The App Store Connect record problems from the Mac submission show that this is easy to get wrong. Sort the Mac record first, then add iOS to it.
- **Sync correctness.** A finance app that duplicates or loses a transaction loses trust. Budget real time for two-device and conflict testing, and keep the `.pig` backup prominent as a safety net.

## Order of work

1. Ship Mac 1.0 (record, TestFlight, review, Friday), then the 1.x feature releases (printing, PDF, reports) with the scaffolding.
2. Phase 0 (iOS compiles) and 0b (sync-ready models, tested on Mac).
3. Phases 1 to 5.
4. Ship it as 2.0, the Mac update and the iOS app together, so sync works from day one.
