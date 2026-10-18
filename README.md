# OinklyBudget (Piggybank)

A Mac personal-finance app: registers, bills, budgets, goals, investments and liabilities, reports, reconcile, receipts, CSV import and export, and `.pig` backups. No bank linking, no accounts, no network. Made by Vault Studio.

The Xcode project is in `Piggybank/`. The product plan is in `docs/`. The website is in `website-vaultstudio/`.

## Branches

| Branch | What it is |
|---|---|
| `main` | Version 1.0, the version in App Review. Only fixes for 1.0 go here. |
| `update-1.1` | All work for version 1.1. Merged into `main` when 1.1 is done. |
| `checkpoint` | An older snapshot. Not in use. |

Switch with Xcode's Source Control ▸ Switch, or `git switch main` / `git switch update-1.1`. Tag the 1.0 submission commit `v1.0` and the 1.1 release `v1.1`.

## What is in 1.1

Full plan, with notes, effort and risks: [docs/oinklybudget-1.1-update-plus-features.md](docs/oinklybudget-1.1-update-plus-features.md). Drafted 2026-10-16. Tick a box when the feature is built and tested on this branch.

Rough size: 12 to 16 weeks part-time.

### Fixes from complaints (do first)
- [ ] Receipt picker on the Edit Transaction sheet (add, replace, remove, "no receipt")
- [ ] Side panel opens at one fixed width and can't be dragged
- [ ] Footer bar on every page: decide whether to remove or restyle it

### Shared data file: two users on one Mac, one at a time
- [ ] Prototype check-out and check-in on a file in `/Users/Shared`, tested with two real logins
- [ ] Settings ▸ Data "Data File" section: current file, who has it open, choose, create, move, open recent, close for someone else
- [ ] Last-file bookmark, missing-file screen, never silently start an empty database
- [ ] Lock file with who and since when, read-only open, take over a stale lock
- [ ] Safe write-back, autosave, crash recovery
- [ ] First launch copies existing 1.0 data (original kept untouched), with a `.pig` backup offered first

### Encrypted data file
- [ ] Opt-in "Encrypt data file" with a passphrase (CryptoKit AES-GCM, no third-party code)
- [ ] Recovery key, optional "Remember on this Mac" in the Keychain
- [ ] Encrypted `.pig` backups
- [ ] Update the App Store export compliance answers

### Export to PDF and CSV (replaces printing)
- [ ] Shared report page and Export sheet
- [ ] Every account: Export to PDF and Export to CSV, with a date range
- [ ] Main Transactions page: Export to PDF with a month selector
- [ ] Single transaction to PDF
- [ ] Reports, budget, bills, net worth to PDF (lower priority)

### CSV import that handles any bank file
- [ ] Preview before importing
- [ ] Column mapping, saved per bank
- [ ] Date and amount formats, extra header and summary lines, delimiter and encoding
- [ ] Duplicate handling and Undo import
- [ ] Import Statement… on every account

### Widgets
- [ ] Upcoming bills widget (names and dates only)
- [ ] Reminders and events widget
- [ ] App Group and snapshot writer; no amounts or account details anywhere

### Reports and everyday features (pick from the list)
- [ ] More reports and report options
- [ ] Recurring transactions
- [ ] Split transactions
- [ ] Other "Should have" items as time allows

### Not in 1.1
- Quicken, QIF, OFX and QFX import
- Print command, ⌘P and page setup (use Export to PDF)
- Bank linking, accounts, cloud sync, two people editing at the same moment

### Release
- [ ] Help pages and screenshots for each new feature, release notes, accessibility check
- [ ] Version 1.1, build number up for every upload, schema change only if needed (`PiggybankSchemaV2`)
- [ ] Remove the unused iCloud and push entitlements, add the App Group entitlement
- [ ] TestFlight, App Review notes, website and listing update
