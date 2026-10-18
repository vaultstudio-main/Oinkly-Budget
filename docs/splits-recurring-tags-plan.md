# Plan: splits, recurring transactions and tags (step 2)

Drafted 2026-10-18. Nothing here is started. The database side is done: the models `TransactionSplit`, `Tag` and `RecurringTransaction` exist in `PiggybankSchemaV2`, with the links on `Transaction` (`splits`, `tags`, `recurring`). This step builds the screens and the logic on top of them. About 2 to 3 weeks together.

Data safety rules from `data-integrity-plan.md` apply to all of it: no new stored field without a default, every step that changes data is safe to run twice, and the model rule below.

**Model rule:** V2 has not left this Mac yet, so a missing field can still go into V2 (wipe your own test data after). Decide any missing field in the first day of each feature, before the screens are written. Once V2 is on TestFlight or the store, every change needs V3.

## Order

1. **Splits** first. They touch the most code (every place that reads a category), so they carry the most risk and should get the longest testing time.
2. **Tags** second. Small, and they reuse the report filter work from splits.
3. **Recurring** last. It needs the transaction creation path and the forecast, and it is the only one that creates data by itself.

Each feature ends with: backup and restore, Clean Up, CSV and PDF export, test data, and tests from the data integrity plan (section E).

---

## 1. Split transactions (about 1 week)

**What it does**
- One payment or deposit divided across several categories (a $120 shop split into Groceries $90 and Household $30).
- Edited in the New Transaction and Edit Transaction windows with a "Split" button next to Category.
- The split editor lists rows (category, amount, optional memo). A running line shows total, allocated and left to allocate. Save is blocked until the parts add up to the transaction amount exactly.
- The register shows one row, with the category column reading "Split (3)". Double-click or the detail window shows every part.
- Reports, budgets and the tax report count each part under its own category, once.
- Removing all but one row turns it back into an ordinary transaction.

**Rules**
- Parts have the same sign as the transaction. The sum must equal the amount, to the cent.
- Not allowed on transfers, loan or card payments, ATM withdrawals, opening Deposits or bill payments (their categories are locked).
- Changing the transaction amount on a split asks to adjust the parts. It never silently leaves them out of balance.
- Deleting a category used in a split: the same prompt as today, with the split parts moved to the replacement category.

**Where code has to change** (each one reads a transaction's category today)
- `Transaction` display category and `fixedCategoryTitle`, the register category column, search.
- `LedgerIndex` and `Summary` (month spending by category), `ReportMath`, `ReportInputs`, `ReportCatalog`, `TopSpendingView`, `TaxRelatedReport`, `Budget` spent amounts.
- `CleanUp` (category replace must update split parts), `TransactionCSV` and `StatementExport` (export one line per part, or a "Split" marker, decide in the first day), `StatementImport` (imports never create splits), `DataBackup` (add split records, optional fields).
- `TestData` (add a few splits).
- Edit Transaction and New Transaction windows, and the Transaction detail window.

**Decisions (made 2026-10-18)**
1. CSV export of a split: **one row per part**, same date and payee, so spreadsheets add up by category. Importing that file back gives separate transactions.
2. Budgets and spending reports: **each part counts under its own category.**
3. **Every part needs a category.** Save is blocked until each part has one.

**Day-one findings (2026-10-18)**
- No field is missing from V2 for splits. `TransactionSplit` has transaction, category, amount, memo and order. Whether a transaction is split is `splits.count > 0`, so no new flag is needed.
- Files that read a transaction's category and need a split decision (count of references in brackets): `CleanUp` (9), `RegisterView` (6), `TopSpendingView` (5), `StatementExport` (5), `DocumentBuilders` (4), `Category` (4), `TransactionsView` (3), `OverviewReports` (3), `BillsView` (3), `SpendingReport` (3), `ReportInputs` (3), `DataBackup` (3), `SpendingReports` (2), `RecentTransactionsPanel` (2), `NewTransactionWindow` (2), `BudgetEditView` (2), `Transaction` (2), `InvestmentType` (2), `Budget` (2), and one each in `TransactionDetailWindow`, `IncomeReports`, `BudgetReports`, `BillReports`, `TransactionCSV`, `Reports`, `Investments`, `Bills`.
- `LedgerIndex` does not read categories, so balances and net worth are unaffected by splits.

**Tests**
- A split of 2, 3 and 10 parts; parts that don't add up; negative and positive; editing the amount; deleting a category.
- Spending by category, the budget, the tax report and net worth give identical totals to the same data entered as separate transactions.
- Backup and restore, CSV round trip, Clean Up, 20,000 transactions with 2,000 splits for speed.

---

## 2. Tags (3 to 4 days)

**What it does**
- Many tags on one transaction, such as "Vacation" or "Reimbursable". A tag has a name and a colour.
- Added in New Transaction and Edit Transaction (a token field), and from the register by right-click ▸ Tags.
- Shown in the register as small coloured chips (hidden on narrow windows) and in the transaction detail.
- Reports get a Tag filter. Search matches tag names.
- A Tags screen in Settings: rename, recolour, delete (removes the label from transactions, never the transactions), merge two tags.

**Rules**
- Tag names are unique ignoring case and spaces.
- Deleting a tag asks first and says how many transactions use it.
- Tags are ignored for balances and budgets. They only filter and label.

**Where code has to change**
- New Settings tab, tag picker view, register column, report filter in `ReportInputs`/`ReportCatalog`, `CleanUp`, `DataBackup`, `TransactionCSV` (export a Tags column, import reads one if present), `TestData`.

**Decisions to confirm**
1. Tag a split part or only the whole transaction? Recommendation: whole transaction only.
2. Number of tags shown in the register before "+N". Recommendation: two.

**Tests**
- Add, rename, merge, delete a tag; deleting a tag in use; same name in different case.
- A report filtered by a tag gives the same total as selecting those transactions by hand.
- Backup and restore, CSV round trip.

---

## 3. Recurring transactions (about 1 week)

**What it does**
- A rule: payee, account, category, memo, amount, payment method, frequency, start date and optional end date.
- On each due date the rule adds a **pending** transaction for you to confirm or edit (recommended). A rule can be switched to reminder only (`autoEnter` off).
- A Recurring screen (under Bills or Planning, decide in the first day) lists rules with next date, amount and status, and has add, edit, pause and delete.
- The cash flow forecast on Summary and Reports includes upcoming rule amounts.
- "Make this recurring" from the right-click menu on a transaction fills in a rule from it.

**Rules**
- Catch-up: when the app was closed for weeks, create each missed pending transaction once, up to a sane limit (for example 12), and then say so.
- Never create a second pending transaction for the same rule and date. Running it twice must change nothing.
- Editing a rule changes future entries only. Entries already made are kept.
- Deleting a rule keeps the transactions it made (their link is cleared).
- Pausing keeps `nextDate`. Resuming does not fill the paused period unless asked.
- Rules never write to credit limit accounts in a way that bypasses the credit limit check. A charge that would reach the limit stays pending and flags a warning.
- Locked accounts (Cash on Hand rules allowed only as cash, loans not allowed, cards as charges) follow the same rules as New Transaction.

**Where code has to change**
- A new runner, `RecurringRunner`, called at launch, when the app becomes active, and at midnight. It uses the same creation path as New Transaction so payee memory, balances and the ledger index stay right.
- Recurring screen and rule editor, a menu item, Settings notes.
- `DataBackup`, `CleanUp` (payee and category replace updates rules), `TestData`, the forecast in `ReportTrends`/`ReportMath`, `LedgerIndex` refresh after rule runs.

**Decisions to confirm**
1. Where the screen lives (Bills page tab, or its own sidebar item). Recommendation: a Recurring tab on the Bills & Recurring page.
2. Notification when a pending transaction appears. Recommendation: none by default, optional later.
3. A field that may be missing from V2: `lastRunDate` on the rule, or the scheduling is enough from `nextDate`. Recommendation: `nextDate` is enough; confirm in the first day.

**Tests**
- Monthly rule on the 31st, leap years, weekly and biweekly rules, end dates, paused rules.
- App closed for a month, then opened: the right number of pending entries, none duplicated.
- Running the runner twice in a row.
- A rule on an account that gets deleted.
- Forecast total equals the sum of the rule amounts over the period.
- Backup and restore keep rules and their links.

---

## Shared work after all three

- Backup and restore: new optional records for splits, tags and rules. The backup version stays compatible with 1.0 backups.
- Test data: a few splits, tags and rules in `TestData` so screenshots show them.
- Release notes, Help topics and screenshots (see `help-file-plan.md`, `screenshot-plan.md`, `release-notes-1.1-draft.md`).
- Data integrity checks section E.
- Performance: the register, Summary and reports with 20,000 transactions, 2,000 splits and 200 rules.

## Day-one checklist (before writing any screen)

1. Confirm the three decisions per feature above.
2. List every place that reads `Transaction.category` (search the project) and decide how each handles splits.
3. Decide whether any field is missing from V2. If yes, add it to V2 now and wipe the test data.
4. Make the test data and a way to compare totals before and after, so any change in a total is caught.
