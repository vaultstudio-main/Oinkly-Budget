# Oinkly Budget (Piggybank)

A Mac personal-finance app: accounts of every kind, registers, bills and repeating transactions, budgets, goals, investments and liabilities, reports, reconcile, receipts, CSV import and export, and `.pig` backups. No bank linking, no accounts, no network. Made by Vault Studio.

Version 1.0 (build 5) is the first public release.

## Where things are

| Folder | What is in it |
|---|---|
| `Piggybank/` | The Xcode project (scheme Piggybank): the app, the widget extension and the shared code |
| `docs/` | The release plan, feature list, release notes, App Store text, screenshot notes, data safety plan and the 1.1 plan |
| `website-vaultstudio/` | The Vault Studio website, including the Oinkly Budget pages |
| `scripts/` | `make-help-images.py`, which turns the app's own screenshots into Help, website and App Store pictures |

Never run git inside `Piggybank/Piggybank/Piggybank`: it holds a stray nested repository.

## Branches and tags

| Name | What it is |
|---|---|
| `main` | The 1.0 release. All current work is here. |
| `app-review-original-1.0` (tag), `legacy-1.0-original` (branch) | The build first sent to App Review |
| `check-printing` | Check printing, dropped from 1.0 and kept for later |
| `checkpoint` | An older snapshot, not in use |

## What 1.0 has

The full list, with how each feature works, is in [docs/feature-master-list-1.0.md](docs/feature-master-list-1.0.md). In short:

- **Money:** accounts (checking, savings, cash, cards, loans, investments), split transactions, tags, categories and budgets, reconcile, receipts and PDF bills.
- **Bills and recurring:** a bills calendar with reminders and one-step payments, repeating transactions that wait for you to confirm them, and your own reminders.
- **Menu bar and widget:** one Upcoming Transactions list (bills, repeating transactions, reminders), with no amounts.
- **Planning and reports:** goals tied to accounts, a Budgets page, reports with six-month projections, Liabilities and Investments pages.
- **Data:** Print PDF and Export CSV on account pages, Import Statement for any bank's CSV (formats can be saved), `.pig` backups that include reminders and saved import formats, and a safety copy before the first open.
- **No encryption:** the data file is plain. The app uses no encryption of its own.
- **Help:** a topic for every feature, with pictures taken by the app itself.

## Data safety

The database is `PiggybankSchemaV3` (a migration plan carries V1 and V2 files forward). Reminders and saved CSV import formats are stored in the database, so backups carry them. See [docs/data-integrity-plan.md](docs/data-integrity-plan.md) for the protections and tests. Debug-only launch tests live in the source under `Logic/SharedData/`.

## Release

Steps left for the owner are in [docs/1.0-release-plan-final.md](docs/1.0-release-plan-final.md): export compliance "none", App Store text and screenshots, website upload, swapping build 5 into review, TestFlight and release.

## After 1.0

The 1.1 plan is [docs/1.1-plan.md](docs/1.1-plan.md): automatic transfer between computers, search by tag, default account artwork, and menu clean-up.
