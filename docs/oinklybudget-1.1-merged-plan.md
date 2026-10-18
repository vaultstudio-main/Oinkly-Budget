# OinklyBudget 1.1: merged plan (1.2 pulled in)

Decided 2026-10-18. 1.1 has a longer release window, so everything that was planned for 1.2 now ships in 1.1. Two reasons from the owner: Help should describe the finished app once, and the shared data file and the database change should come early, so no one needs a separate upgrade path later.

Everything in `oinklybudget-1.1-update-plus-features.md` still applies. This file adds the 1.2 items and sets the order.

## What moves in

- The shared data file (two Mac logins, one at a time). A prototype is on the `shared-data-prototype` branch.
- The one database change (`PiggybankSchemaV2`): primary checking on the account, split transactions, recurring transactions, tags, and routing numbers as real fields.
- PDF pages for Reports and Summary (the builders exist but have no button).
- Attachments beyond receipts (PDF statements kept with an account).
- Check printing (optional).
- Settings for default paper size and export style.
- Keyboard shortcuts review and the accessibility pass.
- Widget options (choose which bills or reminders), only if time allows.

## Order of work

1. **The database change (V2).** First, because everything else builds on it and an existing database has to open after the update. About 1 week.
2. **Splits, recurring transactions and tags.** On top of V2. About 2 to 3 weeks together.
3. **The shared data file.** Rebuilt on the V2 schema and the encryption vault. About 2 to 3 weeks, and it needs a test with two real Mac logins.
4. **Exports and extras:** PDF buttons, attachments, check printing, default settings. About 1 week.
5. **Shortcuts and accessibility pass.** About 3 days.
6. **Help, screenshots, release notes, TestFlight and submission.** Last, so they describe the finished app. About 1 to 2 weeks.

About 8 to 11 weeks in all.

## The one database change (V2)

Every new stored field goes in V2 together, with a default, so the migration stays a lightweight automatic one. Anything not listed here can't be added later without another migration.

| Where | New | Why |
|---|---|---|
| Account | `isPrimaryChecking`, `wireRoutingNumber`, `digitalRoutingNumber` | Primary checking is a Mac setting today. Wire and digital numbers are packed into the one routing field today. |
| Transaction | `isOpeningDeposit` | The opening Deposit is found today by its payee, category and method. A flag is exact. |
| Transaction | splits (new model `TransactionSplit`: category, amount, memo) | One payment across several categories. |
| Transaction | tags (new model `Tag`: name, colour) | Usable in reports. |
| Transaction | link to its recurring rule | Recurring transactions. |
| New model | `RecurringTransaction` | Paycheque, rent, and so on. |
| Category | `isTaxRelated` | The tax report matches by name today. |
| Payee | `lastMemo`, `lastMethod` | Autofill without searching history. |

Ten models become thirteen.

How the migration is built and tested:

- A frozen copy of all ten current models is kept as `PiggybankSchemaV1`, and a lightweight stage moves to V2.
- Test by building the 1.0 version from `main`, filling it with data, then opening that same database with the new build. Repeat with a large data set (about 4,000 transactions) and with an encrypted vault.
- A one-time step after the migration unpacks the routing numbers and sets the opening-deposit flag.
- Backup reminder in the release notes, and an automatic safety copy of the database file before the first V2 open.

## Decisions

1. **Recurring transactions:** recommend that a rule creates a *pending* transaction on its due date, which you confirm or edit, rather than reminding only. It also feeds the cash flow forecast.
2. **Splits:** edited in the New and Edit Transaction windows. A split transaction shows once in the register and once per category in reports.
3. **Tags:** many per transaction. Shown in the register and used as a report filter.
4. **Check printing and attachments:** in, but last in the order of work; first to drop if the schedule slips.
