# OinklyBudget for iPhone and iPad — plan

Drafted 2026-10-15. Nothing here is started. The Mac release comes first.

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

**Recommendation:** ship **A** in the first iOS release, with a clear "Move my data to this device" flow built on the existing `.pig` backup. Then take on **B** as a separate release once the phone app is stable. There is already a note in the repo that sync was deliberately deferred, and the model is easier to adapt once you know what the phone version actually needs.

Whatever you pick, decide before submitting: it changes the privacy page, the App Store privacy answers and the Help text.

If you go with B later, plan these checks first:

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
| 1. Skeleton | Phone tab layout, iPad split view, account list, register list, transaction detail, add and edit transaction. | 1 to 2 weeks |
| 2. Core flows | Bills and bill pay, transfers, categories, budget screen, goals, reminders, settings. | 1 to 2 weeks |
| 3. The rest | Investments, liabilities, reports, receipts, `.pig` backup and restore, CSV import and export, Help and About. | 1 to 2 weeks |
| 4. Phone extras | Widgets, Face ID lock, Spotlight and Shortcuts if wanted, haptics. | 3 to 5 days |
| 5. Polish and release | Accessibility pass, iPad multitasking, screenshots, TestFlight, App Store submission. | 1 to 2 weeks |

Estimate for one developer part-time: about 6 to 10 weeks to a first TestFlight build. Phase 1 is where the risk is; do a thin vertical slice first and judge it before committing to the rest.

## Release and App Store

- **Universal Purchase.** Use the same bundle ID family and the same App Store Connect app record so one purchase covers Mac, iPhone and iPad. The Mac app is currently `dev.vaultstudio.oinklybudget`; adding iOS to the same record needs the same bundle ID (check this before the Mac app is final, because changing bundle IDs later is painful).
- **Price.** Decide whether the iPhone and iPad version is included in the $9.99 purchase or sold separately. Universal Purchase means included.
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
- **Sync expectations.** Users will assume a phone app syncs. The listing must say plainly that it does not (if you choose A) and offer a clear transfer path.
- **Two code paths.** `#if os(macOS)` sprinkled everywhere gets hard to maintain. Keep the platform differences in a small number of wrapper files.
- **Bundle ID and record.** The App Store Connect record problems from the Mac submission show that this is easy to get wrong. Sort the Mac record first, then add iOS to it.
- **Time.** This competes with the Windows plan. Decide which comes first (see below).

## Order of work

1. Finish the Mac release (record, TestFlight, review).
2. Phase 0 of this plan, which is also the cheapest way to find out how portable the code really is.
3. Decide the data transfer story (A, B or C) before building the phone UI.
4. Phases 1 to 5.
5. Windows, if still wanted. Note that the Windows plan also has a Mac-first Phase 0 (the `.pig` format and core logic), and the two plans share the same backup format.

## Decisions needed from you

1. Standalone with manual transfer first, or iCloud sync before the first iOS release?
2. Included in the $9.99 purchase (Universal Purchase), or a separate price?
3. iPhone and iPad together from day one, or iPhone first and iPad as a fast follow?
4. Minimum iOS version (18 recommended).
5. Are widgets and Face ID lock in the first release or a later one?
6. iOS before or after Windows?
