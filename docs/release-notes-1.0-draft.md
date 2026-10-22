# Release notes: 1.0 (draft)

Drafted 2026-10-18 for the first public release, version 1.0, build 5. It lists every feature of the app, so the same text can be used as the launch notes. The source is `feature-master-list-1.0.md`; if a feature is added or dropped there, change it here too. Items marked are planned but not built yet; delete the line if the feature is dropped. Final wording is polished in step 6 after everything ships.

This text goes in four places: `Views/ReleaseNotesWindow.swift` (the release at the top of `releases`, with the same sections), the App Store description (the short version below), the website, and the support page.

## App Store "What's New" (short version)

Goals that follow your accounts, six-month projections on every report, a reworked Summary with your priority bills, export to PDF and CSV, importing bank statements with a preview, widgets, and many smaller improvements. Your data stays on your Mac.

## In-app release notes (full version)

**Version 1.0 · First release**

### Accounts
- Opening balances are now a real, locked Deposit transaction (payee Deposit, category Deposit, method Bank Deposit, memo Opening balance, reconciled) on bank and investment accounts. Change the amount in Edit Details. Cash on Hand has none.
- A savings goal can create its own account, with an account number, institution and the amount saved so far, which becomes its opening Deposit.
- Mark one checking account as your primary. It is pinned under Cash on Hand in the side panel.
- Routing numbers belong to checking accounts only, and a checking account can hold ACH, wire and digital routing numbers. Wire routing numbers can include letters.
- A new account details layout: facts in even columns, unreconciled and pending counts with amounts, and a loan's progress, payments left and payment due all in one place.
- Cash on Hand: New Cash Transaction is now a button on the Cash on Hand page instead of a File menu item.

### Goals and planning
- Goals follow your accounts. Link a savings goal to a checking or savings account, or a payoff goal to a loan or card, and progress updates by itself. Unlinked goals work as before.
- Every linked account shows a Goal section beside its details: target date, status (on track, behind, past the date, reached), what you need each month, your pace over the last three months, what it takes to catch up, an estimated finish date and a progress bar. It looks the same on every kind of account.
- A reached goal is kept with its final amount and stops following the account.
- The Planning page lists loans with maturity dates and estimated payoff dates beside your goals, and says whether a loan will be paid off before it matures.
- New Budgets page in Overview: budgeted, spent and left for every category that has a budget. Categories with a zero budget are hidden. Edit budgets in Settings ▸ Categories.

### Reports and the Summary
- Reports: one period button instead of separate tabs, line charts, and six-month projections (dashed) on every report: net worth, cash flow, debt and loans, goals, budgets, spending, income, bills and investments.
- Cards without enough data keep their full size and say what is needed, instead of shrinking away.
- A reworked Summary: Income & Spending, Liabilities and Investments cards on top; then Priority Bills; Net Worth Over Time with the next six months; a Summary card with assets and liabilities; loans progress; savings goals; the last 15 transactions; income and spending flow; and top spending categories.
- Priority Bills: your next five important bills that are overdue or due within 20 days, on the Summary. The orange alert that used to sit at the top is replaced by this card (the Bills page keeps its alert).
- Liabilities has a Paid Down card for 3 months, 6 months and a year, with projections.
- Investments has Growth cards for 3 months, 6 months and a year, and a Projection of Growth. The sample data is gone; cards wait for your own data.
- The tax-related report follows a new "Counts as tax-related" setting on each category (starter categories like Charity, Healthcare and Taxes are flagged for you).

### Transactions
- Status colors: green for reconciled, yellow for pending, red for unreconciled, in the register and in the status menus.
- Edit Transaction now has everything New Transaction has, including adding, replacing or removing a receipt.
- Autofill: type a payee you have used before and the category, amount, memo and payment method fill in.
- Clean Up (Settings ▸ Clean Up): find and replace in payee names, merge look-alike payees, and move a category's transactions to another category (with the option to delete the old custom categories). Undo the last change.
- Split transactions: one payment across several categories, with parts that must add up to the total.
- Tags: label transactions, show tags in the register.
- Recurring transactions: rules for paycheques, rent and more that add pending transactions for you to confirm, and feed the cash flow forecast. The Recurring tab looks like the Bills tab, with a calendar, and repeating transactions show in the menu bar, in reminders (no amounts) and in the widget.

### Export and import
- Print PDF and Export CSV on every account and on the Transactions page, with an Export sheet for account, period (month, year or from a date) and paper size. A single transaction can be saved as a PDF from its detail window. To print, open the PDF in Preview.
- Import Statement on every account: preview the rows with counts of new, already-there and unreadable ones; set the columns, date format, separator and amount style if the file isn't recognised; save the format under a name and have it detected next time; skip transactions already in Oinkly Budget; tidy bank text in payee names; and Undo removes everything an import added. CSV only.
- Default paper size and export style in Settings.

### Your data
- Data & Backup is one tab: your counts, Export Backup and Import Backup, Erase All Data and the version. Backups carry all the new 1.0 information.
- Updates are safer: a copy of your data is made before the first open in 1.0, and a file that can't be opened shows an error instead of an empty app.

### Widgets and the menu bar
- Two widgets in small, medium and large: Upcoming Bills (bills and repeating transactions) and Reminders. Edit a widget to choose which bills (all or important only), how far ahead and whether repeating transactions show, or which reminders. They show names and dates only, never amounts or account details.
- The menu bar pop-up shows this month's bills, with important bills for the next 30 days first.

### Around the app
- The side panel has colored icons by account type, a fixed width and can't be collapsed. Budgets is in Overview.
- A status bar along the bottom of every page, with a Help link.
- The window title reads "Oinkly Budget".
- Help and Release Notes open in bigger windows.
- Keyboard shortcut and accessibility improvements (VoiceOver, larger text).
- Works on macOS 15 and later.

## Checks before this is final

1. Every line is true of the shipped build (read each one against the app).
2. Every item is either built or deleted.
3. The feature list matches `feature-master-list-1.0.md`.
4. The macOS minimum, version and build number are right.
5. The short App Store text fits the character limit in App Store Connect.
6. Copy the final text to all four places listed at the top.
