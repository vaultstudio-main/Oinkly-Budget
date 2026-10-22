# Release notes: 1.0

Final text for the first public release, version 1.0, build 5. It describes the whole app, with no comparison to any earlier build. The same text is in `Views/ReleaseNotesWindow.swift`. The short version goes in App Store Connect as "What's New" and on the website.

## App Store "What's New" (short version)

Welcome to Oinkly Budget 1.0. Accounts of every kind, a bills calendar with reminders and one-step payments, recurring transactions, split transactions and tags, goals that follow your accounts, budgets, reports with six-month projections, CSV import and PDF and CSV export, a menu bar item and a widget. Your data stays on your Mac.

## In-app release notes (full version)

**Version 1.0 · First release**

### Why it's different
- Your money stays yours. Everything is kept on your own Mac, with no account to create and no sign-in. Nothing is sent anywhere.
- Paying a bill is one step that does everything: it comes out of your account, comes off what you owe, ticks the bill off, and files under the right category.
- Credit limits are real. A charge that would reach a card's limit is stopped before it's saved.
- Cash is part of the picture. Cash on Hand fills from ATM withdrawals, so what's in your wallet stays honest.
- Mistakes are hard to make. Dates, categories, methods and amounts are changed in one deliberate place, never by a stray click or scroll.
- Receipts and bills travel with the transaction: attach a photo or the PDF, or mark it as having none.
- Backups are one file. Save everything and restore it whole.

### Accounts
- Checking, savings, cash, credit cards, loans, mortgages, investments and assets, all in one place, in a side panel with colored icons and folders by type.
- Every bank account starts with a real, locked Deposit for its opening balance (payee Deposit, method Bank Deposit, memo Opening balance), so the register and the balance always agree. Change it in Edit Details.
- Mark one checking account as your primary. It is pinned under Cash on Hand in the side panel. Checking accounts can hold ACH, wire and digital routing numbers.
- Each account's page lays its details out in even columns, with unreconciled and pending counts and amounts, and a loan's progress, payments left and payment due in one place.
- Cash on Hand is built in and can't be deleted: an account for the money you carry, with no bank details, always cash. New Cash Transaction records cash you spend or receive, and ATM Withdrawal moves cash from a checking or savings account into it.
- Credit cards keep a card number, credit limit, APR, minimum payment and payment due date. New Credit Card Charge refuses a charge that would reach the credit limit.
- Loans keep the amount borrowed, interest rate, start and maturity dates, and the payments left. Auto accounts can be a loan or a lease, with a photo and VIN.
- Account names are limited to 30 characters.

### Transactions
- A register for every account, plus one page with every account's transactions together.
- Status colors: green for reconciled, yellow for pending, red for unreconciled.
- Categories match the direction: expense categories for money out, income categories for money in. Payment methods, including your own, and a check number for checks.
- Autofill: type a payee you have used before and the category, amount, memo and payment method fill in.
- Edit Transaction has everything New Transaction has, including adding, replacing or removing a receipt.
- Split a payment across several categories. The parts must add up to the total, and reports count each part under its own category.
- Tags: colored labels, as many as you like on a transaction, shown in the register and managed in Settings ▸ Tags.
- Double-click any transaction for a closer look in its own window, with the receipt shown larger. Open several side by side. Nothing changes until you press Edit.
- Receipt photos or PDF bills on checking accounts and credit card charges, or mark a transaction as having no receipt. Card payments never have one.
- Clean Up (Settings ▸ Clean Up): find and replace in payee names, merge look-alike payees, and move a category's transactions to another category, with Undo.

### Bills, recurring and payments
- Bills & Recurring has two tabs. Bills shows a calendar, this month's bills to tick off, and every bill you have set up with the day it comes out and the amount.
- Recurring transactions: rules for paycheques, rent and more that add pending transactions for you to confirm. The Recurring tab looks like the Bills tab, with a calendar, a month list to tick off, and every rule with its day and amount.
- Reminders before each bill is due, a priority alert for important bills, and a reminder on the morning of each repeating transaction. Reminders for repeating transactions never show an amount.
- Your own reminders in Settings ▸ Reminders: review the budget each month, check bills each week, back up, or anything else, with a notification that opens the page you choose. They are saved with your data, so a backup includes them.
- Loans and credit cards with a due date add their own bill.
- Pick one of eight colours for the picture an account or bill shows until you add a photo, in the account editor and the bill editor.
- Pay a Bill records the payment on both sides, with a payment method and status, and files under the bill's category so it shows in reports. Deleting the payment marks that bill unpaid again. Attach the PDF bill or a photo when you pay.
- Transfers between your own accounts, never touching debts or investments.
- Photos on bills, and a loan's photo is used for its bill.

### Planning and reports
- Goals for saving up or paying off debt. Link a goal to an account and its progress follows the balance by itself. Every linked account shows a Goal section: target date, status, what you need each month, your pace, what it takes to catch up, an estimated finish date and a progress bar.
- A Planning page that lists loans with maturity dates and estimated payoff dates beside your goals.
- First-run setup has a second step for budgets: a monthly amount for every category, with Suggested Amounts, Clear All and Add Your Own. Skip for now still goes straight into the app.
- A Month Outlook page: for any month, what you will have left to save after income, bills and budgets. Link a bill to the payment that paid it, and the outlook uses what really came out, so a bill that ran over or under shows as it happened. Closed months keep their figures.
- A Budgets page: budgeted, spent and left for every category that has a budget. Set budgets and your own custom categories in Settings ▸ Categories. Mark any category as tax-related for the tax report.
- Reports with one period button, line charts and six-month projections on net worth, cash flow, debt and loans, goals, budgets, spending, income, bills and investments. Cards without enough data keep their size and say what is needed.
- A Summary with Income & Spending, Liabilities and Investments cards, your Priority Bills (important bills that are overdue, shown first under their own heading, and the next ones due within 20 days), net worth over time with the next six months, loans progress, savings goals, your last 15 transactions, income and spending flow, and top spending categories.
- Liabilities with a Paid Down card for 3 months, 6 months and a year, and Investments with growth cards and a projection of growth.

### Export and import
- Print PDF and Export CSV on every account and on the Transactions page, with an Export sheet for account, period (month, year or from a date) and paper size. A single transaction can be saved as a PDF from its detail window. To print, open the PDF in Preview.
- Import Statement on every account: preview the rows with counts of new, already-there and unreadable ones; set the columns, date format, separator and amount style if the file isn't recognised; save the format under a name and have it detected next time; skip transactions already in Oinkly Budget; tidy bank text in payee names; and Undo removes everything an import added. CSV only.
- Default paper size and export style in Settings.

### Your data
- Data & Backup is one tab: your counts, Save Backup and Restore Backup, Erase All Data and the version. A backup carries everything, including splits, tags, recurring rules, your reminders, your saved CSV import formats and your preferences.
- Restoring a backup first saves a copy of what is there now, so it can always be undone.
- Upgrades are safe: a copy of your data is made before the first open, and a file that can't be opened shows an error instead of an empty app.
- A reminder to save a backup once you have a very large number of transactions.
- A backup copy: a second copy of your data in a folder you choose, kept up to date on its own with a few older versions. If your data goes missing or can't be opened, the app offers to restore from it. A bottom-bar label shows whether it is up to date.

### Menu bar, reminders and widget
- The menu bar pop-up lists this month's bills and repeating transactions together, each marked, with the date and days to go. Tick a bill to mark it paid. The number beside the pig counts what is due within three days. Closing the window keeps the app running so the item stays.
- With opening at login on, the app starts quietly in the menu bar with no window; the pop-up has an Open Oinkly Budget button, and the window opens by itself if something at start-up needs you.
- One widget, Upcoming Transactions, in small, medium and large: bills, repeating transactions and your reminders in one list, marked and in date order. Edit the widget to choose all or important bills, how far ahead (this month by default), and whether repeating transactions and reminders show. Names and dates only; no amounts.

### Around the app
- A status bar along the bottom of every page with a green, yellow or red dot that shows your data is saved.
- The side panel has a fixed width and can't be collapsed, and Manage Accounts is always at the bottom.
- Keyboard shortcuts for adding things, for the selected transaction and for every page (⌘1 to ⌘8), and VoiceOver support.
- Backups saved as .pig files, with Help and these release notes in the Help menu.
- Opens at full window size. Works on macOS 15 and later.

## Checks before submitting

1. Every line is true of the shipped build (read each one against the app).
2. The feature list matches `feature-master-list-1.0.md`.
3. The macOS minimum, version and build number are right.
4. The short text fits the limit in App Store Connect (4000 characters).
