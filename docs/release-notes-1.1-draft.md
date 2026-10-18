# Release notes: 1.1 (hard draft)

Drafted 2026-10-18 from what is built and what is planned. Final wording is written in step 6 after everything ships. Items marked *(if built)* are planned but not built yet; delete the line if the feature is dropped.

This text goes in two places: `Views/ReleaseNotesWindow.swift` (add a new release at the top of `releases`) and the App Store "What's New" field (shorter version below).

## App Store "What's New" (short version)

Version 1.1 adds goals that follow your accounts, projections on every report, export to PDF and CSV, importing bank statements, an encrypted data file, widgets, and a much improved Summary. Your data stays on your Mac. Before you update, we suggest saving a backup from Settings ▸ Import & Export.

## In-app release notes (full version)

**Version 1.1 · More ways to see where you're going**

### Before you update
- Save a backup first (Settings ▸ Import & Export). The first time 1.1 opens, it also makes a copy of your data in Application Support ▸ Backups ▸ "Before 1.1 (date)". You can delete that copy once you are happy with 1.1.
- Your accounts, transactions, bills, budgets and goals carry over automatically.

### Goals follow your accounts
- A savings goal can follow a checking or savings account, and a payoff goal can follow a loan or card. Progress updates by itself.
- Every linked account shows a Goal section beside its details: target date, status, what you need each month, your pace, what it takes to catch up, and an estimated finish date.
- Make a savings goal and create its account in one step, with an account number, institution and starting balance.
- Estimated payoff and goal dates appear on the Planning page.

### Reports and the Summary
- Reports have one period button instead of separate tabs, and line charts with six-month projections.
- Cards with too little data show a full-size placeholder that says what is missing.
- A reworked Summary: net worth over time, a clearer summary card, and quick cards for income and spending, liabilities and investments.
- Liabilities and Investments show projections and growth.
- New Budgets page in Overview. Budgets set to zero are hidden.

### Bookkeeping
- Opening balances are now a locked Deposit transaction on bank and investment accounts, so every account starts with a real entry.
- Status colours: green for reconciled, yellow for pending, red for unreconciled.
- Autofill: type a payee you've used before and the category, amount, memo and payment method fill in.
- Clean Up (Settings ▸ Clean Up): find and replace payees and categories, and merge duplicates.
- Wire routing numbers can include letters. Checking accounts can hold ACH, wire and digital routing numbers.
- Categories can be marked tax-related, and the tax report follows that.
- Split transactions *(if built)*: one payment across several categories.
- Tags *(if built)*: label transactions and filter reports by tag.
- Recurring transactions *(if built)*: rules for paycheques, rent and more that make pending entries for you to confirm.

### Export and import
- Export any account, or the Transactions page, to PDF or CSV. To print, open the PDF in Preview.
- Reports and Summary can be exported to PDF *(if built)*.
- Import Statement on every account: preview the rows, map the columns, skip duplicates and undo an import.
- PDF statements can be kept with an account *(if built)*.

### Your data
- Encrypt your data file with a passphrase and a recovery key. Backups are encrypted too.
- Widgets show upcoming bills and your reminders, with no amounts or account details.
- Share one data file between two Mac logins, one at a time *(if built)*.

### Around the app
- The side panel is a fixed width and can't be collapsed.
- A status bar along the bottom of every page.
- New Cash Transaction is a button on the Cash on Hand page.
- Bigger Help and Release Notes windows.
- Keyboard shortcut and accessibility improvements *(if built)*.
- Works on macOS 15 and later.

## Open questions before this is final

1. Which *(if built)* items actually ship.
2. The exact macOS minimum version (check the project setting).
3. Whether to list the shared data file as a headline feature or as a smaller item, depending on how the two-login test goes.
4. Tone for the App Store text: keep it to one short paragraph, no sales language.

## Where this must be copied to

- `ReleaseNotesWindow.swift` (full version, new release at the top).
- App Store Connect "What's New" (short version).
- The website product page "What's new" text.
- The App Review notes (still no network, data stays on the Mac, widgets show no financial data, encryption).
