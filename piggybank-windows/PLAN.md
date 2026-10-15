# OinklyBudget for Windows: plan

Status: **draft for a later decision.** Ship the Mac app first. Nothing here is started.
This folder (`piggybank-windows/`) sits beside the Mac app (`Piggybank/`) and the notes (`docs/`) in one repository.

A Windows version is a **new app built to match the Mac one, not a port.** The Mac app is about 14,000 lines of Swift
(3,900 logic, 1,200 models, 9,300 screens) on SwiftUI, SwiftData, UserNotifications, PDFKit, PhotosUI and AppKit,
none of which exist on Windows. Even the logic files use SwiftData models. Swift itself can run on Windows, but that
saves only the language. So the Windows app is a translation of the behaviour, and the Mac app stays the reference.

## Goals
1. Same product: same accounts, bills, budgets, goals, reports, receipts, reminders, backups.
2. **Same `.pig` backup format**, so a person can move their data between Mac and Windows. This is the feature that
   makes the two apps one product.
3. Private by design, exactly like the Mac app: local data, no account, no network, no analytics.
4. Fast with 100,000 transactions, as the Mac app is.
5. Look and feel native to Windows, not a Mac app in a window.

## Non-goals (same decisions as the Mac app)
- No sync between devices. Backup files are the way across.
- No phone or tablet version.
- No web version.

## Recommended stack
| Part | Choice | Why |
|---|---|---|
| Language | C# on .NET 8 (LTS) or later | Mature, fast, `decimal` type fits money, easy for Claude and humans to maintain |
| UI | **WinUI 3** (Windows App SDK) | The native Windows 11 look; MSIX packaging; Microsoft Store friendly |
| Alternative UI | Avalonia | Same C# code runs on Windows, Mac and Linux. Pick this if a Linux build or a unified code base matters more than the most native Windows feel |
| Database | SQLite via `Microsoft.Data.Sqlite` with Dapper, or EF Core | Local single file; migrations; indexes for speed. Same idea as the Mac store |
| Money | `decimal`, stored as text/integer cents | Never floating point. Same rule as the Mac backup file (amounts as text) |
| Charts | LiveCharts2 or ScottPlot | Bar and donut charts for Reports, Summary and Investments |
| PDF receipts | WebView2 or PdfPig/PDFium viewer | Show attached PDF bills |
| Notifications | Windows App SDK app notifications + scheduled toasts | Bill reminders and custom reminders |
| "Menu bar item" | System tray icon with a flyout | Windows equivalent of the Mac menu bar item |
| Icons | Segoe Fluent Icons / Fluent System Icons | The Mac app uses SF Symbols names; each needs a mapping |
| Tests | xUnit | Port the rules with tests first |

Two projects in one solution: `Piggybank.Core` (no UI: models, rules, storage, backup) and `Piggybank.App` (WinUI).
Keeping Core free of UI makes it testable and reusable if an Avalonia or Mac-side tool is ever wanted.

## Planned folder layout (when work starts)
```
piggybank-windows/
├── PLAN.md                  this file
├── Piggybank.sln            Visual Studio solution
├── src/
│   ├── Piggybank.Core/      models, rules, SQLite, backup, CSV (no UI)
│   ├── Piggybank.App/       WinUI 3 app: pages, windows, tray, notifications
│   └── Piggybank.Tests/     xUnit tests, golden .pig fixtures
├── fixtures/                .pig files exported from the Mac app (test data)
└── tools/                   packaging and signing scripts
```

## Screens to build (from the Mac app)
Sidebar pages: Summary, Transactions, Reports, Liabilities, Investments, Bills, Planning, Manage Accounts, and one
register per account. Windows and dialogs: New Transaction, New Cash Transaction, New Credit Card Charge, ATM
Withdrawal, Update Investment Price, Transfer, Pay a Bill, Edit Transaction, Transaction detail, receipt viewer,
account setup and edit, goal and bill editors, Reminders editor. Settings: General, Reminders, Accounts, Categories,
Payment Methods, Data, Import & Export. Also: boot and startup checks, Help, Release Notes, About, tray item.

## Architecture
- **Core** owns: models, SQLite store, ledger and balance calculations, reports, bills, loans, goals, budgets,
  backup import and export, CSV import and export, and the startup repair checks.
- **App** owns: windows, pages, view models, tray item, notifications, settings and Help.
- **Ledger snapshot:** the Mac app computes balances, monthly flows and reports from a background snapshot so pages
  stay quick at 100,000 transactions. Do the same here: compute in a background task into sorted per-account arrays,
  invalidate on save, and never load every row to render a page.
- **Queries scoped to what is shown:** one month or one search at a time, with a database index on date and account.

## The `.pig` backup format (must stay identical)
Defined by `Piggybank/Piggybank/Logic/DataBackup.swift` (in the Mac app folder). It is one JSON file, `BackupFile`, `version = 1`:
- Top-level lists: `categories`, `accounts`, `payees`, `transactions`, `holdings`, `bills`, `goals`, `paymentMethods`,
  and an optional `settings` object.
- **Money amounts are strings**, never numbers. Dates are numbers: seconds since 1970 (Unix time).
- Optional fields added later (goals, payment methods, settings) are absent in older files and must default.
- Account and category references are by index or name inside the file, as the Mac code does.
- Receipts and photos are embedded as base64 data. Verify against the Mac file before relying on this.
- **Acceptance test:** export a `.pig` from the Mac app (the test data one), import it on Windows, check every total
  matches, export from Windows, import on the Mac, check again. Never change the format without bumping `version` on
  both apps together.

## Map: Mac code to Windows modules
| Mac (`Piggybank/Piggybank/...`) | Windows module | Notes |
|---|---|---|
| `Models/*.swift` | `Core/Models` | Account, Transaction, Category, Bill, Goal, Holding, Payee, payment methods. Keep the same rules (live/deleted flags, transfers, locked categories) |
| `Models/DefaultCategories.swift` | `Core/Seed/Categories` | Same built-in category keys, so backups line up |
| `Logic/Bills.swift`, `LoanBill.swift` | `Core/Bills` | Due dates, reminders, paid-state, loan bills |
| `Logic/Reports.swift`, `SpendingReport.swift`, `Trend.swift`, `Summary.swift` | `Core/Reports` | Period ranges, totals, top categories |
| `Logic/Liabilities.swift`, `LoanProgress.swift` | `Core/Liabilities` | Owed, payoff fraction, leverage |
| `Logic/Investments.swift`, `HoldingsLedger.swift`, `InvestmentType.swift` | `Core/Investments` | Returns by holding, contributions vs growth |
| `Logic/GoalProgress.swift`, `Budget.swift` | `Core/Planning` | Saving and payoff goals; budgets |
| `Logic/Transfers.swift` | `Core/Transfers` | Both halves, pay-a-bill, ATM, credit limit checks |
| `Logic/LedgerIndex.swift`, `BalanceCache.swift` | `Core/Ledger` | Background snapshot and cache |
| `Logic/DataBackup.swift` | `Core/Backup` | Format compatibility, see above |
| `Logic/TransactionCSV.swift` | `Core/Csv` | Import and export |
| `Logic/StartupChecker.swift` | `Core/Checks` | Same repairs on launch |
| `Logic/BackupReminder.swift` | `Core/Backup` | Thresholds 50,000 and 100,000 transactions |
| `Logic/CustomReminders.swift`, `BillNotifier.swift` | `App/Notifications` | Windows scheduled toasts |
| `Views/*` (53 files) | `App/Pages`, `App/Windows` | See phases |
| Help, Release Notes | `App/Help` | Reuse the same text |
| Settings tabs | `App/Settings` | General, Reminders, Accounts, Categories, Payment Methods, Data, Import & Export |

## Phases
Each phase ends with something you can run and judge. Stop after any phase if it isn't worth continuing.

1. **Spike (a few days).** WinUI 3 window with a sidebar, SQLite, and `.pig` import that lists accounts and totals.
   Proves the stack, the format and the packaging. Decide go or no-go here.
2. **Core rules with tests.** Models, ledger, transfers, bills, loans, goals, reports, CSV. Port the Mac test data
   generator so both apps produce the same numbers. Golden test: same `.pig` in, same totals out.
3. **Main pages.** Summary, Transactions, account registers (month-scoped, running balance), New Transaction and the
   other entry windows, Edit transaction, transaction detail window.
4. **Bills and planning.** Bills calendar and list, Pay a Bill, Planning and goals, Reports, Liabilities, Investments.
5. **Everything else.** Receipts (photos and PDFs), Settings, reminders and tray item, backups and restore, Erase All
   Data, Help and Release Notes, first-run account setup.
6. **Polish and performance.** 100,000-transaction load test, high-DPI and dark mode, keyboard navigation and screen
   reader labels, installer, update path.
7. **Store and release.** Packaging, signing, listing, privacy page update for Windows, website page.

Rough effort, with Claude doing most of the typing and you testing: phases 1 to 2 are the foundation, phases 3 to 5
are the bulk, and it is weeks of calendar time, not days. Every new feature after that is built twice.

## Distribution
| Option | Cost | Notes |
|---|---|---|
| **Microsoft Store (MSIX)** | One-time developer registration (about $19 individual) | Store handles signing, updates and payments. Closest equivalent to the Mac App Store. Microsoft's revenue share is lower than Apple's |
| **Direct download** | Code-signing certificate (yearly) | You host it, handle updates, payments (e.g. a payment provider) and SmartScreen reputation |
| Both | Both costs | Common approach |

Plan on the Microsoft Store first. Pricing could be a one-time purchase to match the Mac version.

## Risks and open questions
- **Testing on real Windows:** needs a Windows PC (or a VM) and a couple of real-world machines. Claude can build and
  run it; installs, high-DPI and driver quirks need a person.
- **Two code bases:** every rule must change in both places. Mitigation: the shared golden test files and `.pig` fixtures.
- **Feature parity vs timing:** decide whether Windows 1.0 can launch without the most complex pieces (investments
  holdings, goals payoff) and add them in 1.1.
- **Support load:** a second platform doubles questions and support email.
- **Market:** Windows has more finance software and fierce competition. The advantage is the privacy story and the
  matching Mac app.
- **Naming and branding:** reuse "OinklyBudget" if the name is free on the Microsoft Store.

## Decisions you need to make
1. Go or no-go after the spike?
2. WinUI 3 (most native) or Avalonia (also gives a Linux build)?
3. Microsoft Store only, or Store plus direct download?
4. Price: same as Mac ($9.99) or different?
5. Launch together with feature parity, or an early 1.0 with a smaller set?

## Before starting
- Mac app released and stable.
- A Windows 11 PC or VM available for testing.
- A Microsoft Partner Center developer account.
- A frozen `.pig` format and a set of Mac-exported fixture files committed to the repo.
