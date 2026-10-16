# OinklyBudget for iPhone and iPad — plan

Drafted 2026-10-15, decisions made the same day. Nothing here is started. The Mac release comes first.

## Decisions (made)

1. **iCloud sync ships with the first iOS release.** Mac, iPhone and iPad stay in step.
2. **$9.99, one purchase for all of them** (Universal Purchase).
3. **iPhone and iPad together** from day one.
4. **Widgets and Face ID lock are in the first release.**
5. **The Windows version is dropped.** iOS is the only other platform. The `piggybank-windows/` plan is retired.

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
| 0. Prepare | Add iOS destination, get Models and Logic compiling on iOS, wrap AppKit calls, add `PlatformImage`. | 2 to 4 days |
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

1. Finish the Mac release (record, TestFlight, review).
2. Phase 0 (iOS compiles) and 0b (sync-ready models, tested on Mac).
3. Phases 1 to 5.
4. Ship the Mac update and the iOS app together so sync works from day one.
