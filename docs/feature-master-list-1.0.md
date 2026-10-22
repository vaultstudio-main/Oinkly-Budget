# 1.0 feature master list (every feature in the first release)

Drafted 2026-10-18 from the git history of `main` and the current app. This is the single source for four documents: the Help file, the screenshots, the website and the release notes. If a feature is not here, it is not documented anywhere, so add it here first.

- **Status:** Built = in the app now. If a feature is dropped, delete its rows here and in the four documents.
- **How it works:** written for Help and the website. Check each line against the running app before publishing (button names, menu paths).
- **Shots:** screenshot IDs. The full list, with setup and where each is used, is at the end of this file.

---

## A. Accounts

### A1. Opening balance is a locked Deposit (Built)
- When you give a bank or investment account an opening balance, the app creates a real transaction: payee Deposit, category Deposit, method Bank Deposit, memo "Opening balance", status Reconciled.
- It is locked, like payments and transfers, so it can't be edited or deleted from the register. Change the amount in the account's Edit Details (opening balance field); the transaction updates, or is removed if you set it to zero.
- Applies to checking, savings, investment and similar accounts, but not Cash on Hand.
- A savings goal that creates its own account records its starting amount the same way.
- Why: every account starts with a real entry, so the register and the balance always agree, and no empty deposit slip is left behind.
- Shots: S-A1a (register with the locked Deposit), S-A1b (Edit Details with the opening balance field).

### A2. Primary checking account (Built)
- Mark one checking account as primary in Edit Details. It is pinned under Cash on Hand at the top of the side panel and labelled "Primary Checking".
- Only one account can be primary; setting a new one clears the old one.
- It travels with backups.
- Shots: S-A2 (side panel with the primary account pinned).

### A3. Routing numbers (Built)
- Only checking accounts have routing numbers. Savings and others no longer ask for one.
- A checking account can hold three: ACH routing, wire routing (may include letters) and digital routing.
- Shown in the account's details with the others, masked rules unchanged for account numbers.
- Shots: S-A3 (Edit Details, routing fields for a checking account).

### A4. Account details layout and goal section (Built)
- The details panel puts facts into even columns with no empty gaps: type, institution, balances, number, activity for the month, unreconciled and pending counts with amounts stacked.
- Loans show the loan facts (original amount, monthly payment, paid off so far, still owed, interest rate, payments left, maturity date, payment due, this month's payment, started, payments to maturity, needed per month and a progress bar).
- If a goal follows the account, a Goal section sits beside the details, the same on every kind of account (see D1).
- Shots: S-A4a (credit card), S-A4b (loan), S-A4c (savings), all with the Goal section.

### A5. Cash on Hand button (Built)
- New Cash Transaction is a big blue button on the Cash on Hand page. It is no longer in the File menu.
- Shots: S-A5.

### A6. Side panel and window shell (Built)
- Colored icons that match each account type; folders for Checking & Savings, Credit Cards, Mortgages & Loans, Investments and Assets.
- Fixed width, can't be dragged, and can't be collapsed.
- A status bar along the bottom of every page: what you are looking at on the left, and on the right a dot for the database (green "Database · Saved", yellow "Saving…" while changes are written, red "Problem" if saving keeps failing, with the last saved time on hover) and, when sharing is on, a dot for the shared data (green Saved, yellow Not saved yet and click to save now, red Problem). Help is in the Help menu (⇧⌘/).
- Budgets appears in Overview.
- Window title is "Oinkly Budget".
- Shots: S-A6 (whole window).

---

### A7. Picture colours (Built)
- The picture the app draws for an account or bill without a photo can be given one of eight colours (Ocean, Berry, Sunset, Forest, Indigo, Gold, Rose, Graphite) in the account editor and the bill editor, under Picture Colour. Automatic keeps the colour of the account group.
- The choice shows on the account details card, in goals and in the bills lists, and it is saved in backups. A bill with no colour of its own uses its loan's.
- Kept in its own record in the database (data format 4), found by account type and name or by the bill's creation time, so renaming an account in its editor carries the colour along. Photos still win over the drawn picture.
- New pictures and custom artwork are planned for 1.1.

## B. Transactions

### B1. Status colors (Built)
- Reconciled is green, Pending is yellow, Unreconciled is red, in the register and in the status menus.
- Shots: S-B1 (register showing all three).

### B2. Edit Transaction has everything New Transaction has (Built)
- Date, payee, category, amount, method, memo, status and receipt (add, replace, remove or mark "no receipt"), in one sheet. Open it by right-click ▸ Edit Transaction, or Edit in the detail window.
- Shots: S-B2.

### B3. Autofill (Built)
- Type a payee you have used before and the category, amount, memo and payment method fill in from the last time.
- Only on an exact match of the payee; you can change anything afterwards.
- Shots: S-B3 (New Transaction with an autofilled payee).

### B4. Export and print (Built)
- Every account page has Print PDF and Export CSV. The Transactions page has them for all accounts. One transaction can be saved as a PDF from its detail window.
- The Export sheet asks for: account (or all accounts), period (a month, a year, or from a date), and paper size. Then a save panel.
- The PDF has a running balance and repeating headers. To print, open the PDF in Preview.
- The CSV uses the layout Import Statement reads, so it round-trips.
- Settings has a default paper size and export style; the Export sheet starts from them.
- Shots: S-B4a (Export sheet), S-B4b (a page of the PDF in Preview), S-B4c (account page buttons).

### B5. Import Statement (Built)
- Button on every account. Every row goes to that account.
- Choose a CSV file. The sheet shows a preview table with counts: new, already there, problems.
- If the headers aren't recognised, "How this file is read" lets you set: whether there is a header row, separator (comma, semicolon, tab, bar), date column and date format (with a warning when month-first and day-first are both possible), payee, memo, category, amount (single column, or separate debit and credit), "positive amounts are charges" for credit card files, and comma-decimal numbers (1.234,56).
- Options: skip transactions already in Oinkly Budget, tidy bank text in payee names, fill categories from payees you have used before.
- Save a format with a name ("Chase checking"); it is detected automatically next time.
- After importing: how many were added, skipped as duplicates, left out as unreadable, or had no matching category. "Undo" removes everything that import added.
- Still CSV only. PDF statements can't be imported.
- Shots: S-B5a (preview), S-B5b (how this file is read), S-B5c (result with Undo), S-B5d (saved format).

### B6. Clean Up (Built)
- Settings ▸ Clean Up. Three tools:
  - **Find and replace payee names** across all transactions, with Replace All and Undo Last Change.
  - **Look-alike payees:** groups of near-duplicates with counts; merge selected, or merge all into one name; rename one.
  - **Move a category's transactions:** pick one or more custom categories, choose where the transactions go, optionally delete the old custom categories. Payments, transfers and ATM withdrawals keep their locked categories.
- Shots: S-B6a (find and replace), S-B6b (look-alike payees), S-B6c (move transactions).

### B7. Tax-related categories (Built)
- Mark any category as tax-related ("Counts as tax-related" in the budget editor). Starter categories such as Charity, Healthcare and Taxes are flagged for you.
- The tax report follows the flag instead of category names.
- Shots: S-B7.

### B8. Split transactions (Built)
- One payment across several categories; parts must add up to the total; shown once in the register as "Split (n)"; counted once per category in reports and budgets.
- Shots: S-B8a (split editor), S-B8b (register row), S-B8c (detail window).

### B9. Tags (Built)
- Labels with colours; many per transaction; shown as chips in the register; Settings screen to rename, recolour, merge, delete. Tags stay in the transaction area only: no overview page (Summary, Reports) has a tag selector (decided 2026-10-21).
- Shots: S-B9a (tag picker), S-B9b (register with chips), S-B9d (Tags settings).

### B10. Recurring transactions (Built)
- Rules (payee, account, category, amount, method, frequency, start and end) that create pending transactions on each due date for you to confirm. Pause, edit, delete. Feeds the cash flow forecast.
- The Recurring tab is laid out like the Bills tab: tiles (in and out this month, next up, rules) and the month's list on the left, where each date is ticked off (a date waiting for you is added by ticking it; an entry a rule made is ticked to confirm it); a calendar with a dot on each date, an Add Recurring button and an All Rules list in the sidebar (every rule with the day it comes out and the amount, with edit, pause, resume and delete).
- Repeating transactions also show in the menu bar pop-up (in the same list as bills, marked "Repeating", and counted in the number beside the icon), in reminders (a notification on the morning of each date, with no amount) and in the Upcoming Bills widget (names and dates only, switch off in Edit Widget).
- Shots: S-B10a (rules screen), S-B10b (rule editor), S-B10c (a pending entry made by a rule).

---

## C. Bills, reminders and the menu bar

### C1. Priority Bills on the Summary (Built)
- **Your own reminders and saved CSV import formats are kept in the database,** not in the Mac's preferences. They are included in backups and restored with them. Reminders from earlier builds are moved in once, on the first launch. The notifications themselves are still scheduled on each Mac.
- A card under the three top cards listing up to five important unpaid bills that are overdue or due in the next 20 days, soonest first, with amount and "Due in N days". Replaces the orange alert at the top of the Summary. The Bills page keeps its alert.
- Make a bill important in its edit form.
- Shots: S-C1.

### C2. Menu bar (Built)
- The menu bar pop-up has one list for the current month: bills and repeating transactions together, soonest first, each marked "Bill" or "Repeating", with the date and how many days away it is. Tick a bill to mark it paid. The number beside the icon counts bills and repeating transactions due within three days. Settings: show in menu bar, open at login.
- Shots: S-C2.

### C3. Widgets (Built)
- One widget, **Upcoming Transactions**, in three sizes. It lists what the menu bar item lists, in one list: bills, repeating transactions and your own reminders, each marked Bill, Repeating or Reminder, overdue first and then soonest first. Names and dates only: no amounts, balances or account details ever appear.
- **Small:** three lines, each with a day word (Today, Tomorrow, Friday, Oct 24). **Medium:** four lines with the marker and day word, and a count line under the title. **Large:** nine lines, each with the date and how many days away it is ("Fri, Oct 24 · in 3 days"), and a summary of how many bills, repeating transactions, reminders and overdue items there are.
- **Choices.** Right-click the widget and choose Edit Widget: Bills (all, or important only), Look ahead (this month, 7, 14 or 30 days), Include repeating transactions, Include my reminders. The default is this month, the same as the menu bar item.
- It reads a small file the app writes on your Mac and updates after the app saves. If the app has never run: "Open Oinkly Budget to show what is coming up here."
- The separate Reminders widget was folded into this one.
- Add it from the widget gallery (edit widgets on the desktop or in Notification Center).
- Shots: S-C3a (the widget on the desktop in three sizes), S-C3b (widget gallery), S-C3c (Edit Widget choices).

---

## D. Planning, goals and budgets

### D1. Goals follow accounts (Built)
- When you make a goal, link it to an account. A savings goal follows a checking or savings balance (progress is the balance above where it started); a payoff goal follows a loan or card (progress is how far the balance has come down since the goal was made).
- A linked goal takes no manual progress; the balance is the truth. Goals that aren't linked keep their own manual progress.
- A reached goal is frozen with its final amount and stops following.
- On the linked account, a Goal section shows: goal name, target date, status (on track, behind, past the date, reached), needed per month, your pace (last three months), to catch up, estimated finish, paid off or saved, and a progress bar.
- Create an account from a savings goal: give the account number, institution and the current savings, which becomes its locked opening Deposit.
- Shots: S-D1a (goal editor with the account link), S-D1b (goal section on an account, three kinds), S-D1c (Planning page).

### D2. Planning page: loans and estimated dates (Built)
- Loans with maturity dates and estimated payoff dates are listed beside the goals, with whether the loan will be paid off before it matures; goals show an estimated finish date.
- Shots: S-D2.

### D3. Budgets page (Built)
- Overview ▸ Budgets lists every category with a budget: budgeted, spent and left, with a progress bar. Categories with a zero budget are hidden; the count reflects what is shown.
- Click any budget card to change its amount (the same editor as in Settings; your own budgets can be renamed or deleted there).
- A button, Set Hidden and Custom Budgets, opens Settings ▸ Categories, where any category can be given a budget, shown or hidden on this page, and budgets of your own can be added.
- Shots: S-D3.

---

## E. Reports, Summary and the money pages

### E1. Reports (Built)
- One period button (not tabs). Reports for net worth, cash flow, debt and loans, goals, budgets, spending, income, bills, investments, each with a line chart and a six-month projection (dashed).
- Cards with too little data keep their full size and say what is needed.
- Windows (3 months, 6 months, a year) side by side where useful.
- Shots: S-E1a (a report with a projection), S-E1b (period button open), S-E1c (empty card with the needs-more-data message).

### E2. Summary (Built)
- Top cards: Income & Spending, Liabilities, Investments. Then Priority Bills, Net Worth Over Time (last 12 months and the next six), the Summary card (assets and liabilities breakdown), loans progress, savings goals, the last 15 transactions, income and spending flow, top spending categories.
- Shots: S-E2a (top of page), S-E2b (lower page).

### E3. Liabilities and Investments (Built)
- Liabilities: a Paid Down card for 3 months, 6 months and a year, with projections.
- Investments: a Growth card for 3 months, 6 months and a year, and a Projection of Growth. No sample data; placeholders keep their size.
- Shots: S-E3a (Liabilities), S-E3b (Investments).

---

## F. Your data

### F2. Data & Backup settings (Built)
- One Data & Backup tab: counts, Export Data and Import Data (`.pig`), Erase All Data, version. The backup now also carries the new 1.0 fields.
- A reminder to back up once there is a very large number of transactions (a gentle one from 50,000, a firmer one from 100,000).
- Shots: S-F2.

### F3. Safety copy (Built)
- The first time 1.0 opens, it copies your data (data file and receipts) to Application Support ▸ Backups ▸ "Before this update (date)". It stays until you delete it.
- Your data stays in the app's own folder; the widgets don't move it.
- Everything migrates automatically; opening a damaged file shows an error screen and never starts a blank database.
- Shots: S-F3 (Finder showing the Backups folder).

### F4. Only receipts are stored (decided)
- The app stores receipt photos and PDF bills on transactions, and nothing else. PDF statements are not kept with accounts, and there are no other attachments. (Decided 2026-10-18.)

---

## G. Everyday polish

### G1. Bigger Help and Release Notes windows (Built)
- Open at 1100×780 and 860×780. Shots: S-G1 (Help window).

### G2. Keyboard shortcuts and accessibility (Built in part)
- New Go menu: ⌘1 to ⌘8 for Summary, Transactions, Reports, Liabilities, Investments, Bills & Recurring, Planning, Budgets.
- New Transaction menu for the selected transaction: ⌘E Edit Transaction, ⌘I View Details, ⇧⌘R Make Recurring. These do what right-click does, so the keyboard and VoiceOver can reach them.
- Importing, exporting and printing stay on each page's own buttons (Import CSV, Export CSV, Print PDF). The File menu only has the commands that add things.
- Existing shortcuts stay: ⌘N, ⌥⌘N, ⇧⌘A, ⇧⌘T, ⇧⌘B, ⌥⌘U, ⇧⌘/, ⌘, and ⌘Q.
- VoiceOver labels on icon-only buttons, headings on page and card titles, and decorative pictures hidden. Chart descriptions, larger text and the Edit menu are still open; see `accessibility-audit.md`.
- Shots: S-G2 (shortcut list in Help).

### G3. Default settings for export (Built)
- Settings ▸ General ▸ PDFs: **Paper size** (Automatic follows your region, US Letter or A4) and **Style** (Plain black and grey, or With color accents using blue headings).
- Every PDF reads them: account statements and one transaction. The Export sheet starts from the paper chosen here and can still change it for one export.
- Saved in the backup file with the other preferences.
- Shots: S-G3.

### G4. Check printing (not in 1.0, decided)
- Dropped from 1.0 on 2026-10-18: it can't print the magnetic line, is untested on real stock and printers, and few people write checks now. The work is saved on the `check-printing` branch for a later version.

---

## Shot register (every screenshot for Help, website and the App Store)

Rules: light mode, test data (Oinkly Budget ▸ Testing ▸ Fill with Test Data), fixed window size, no real information. Website images are 1600 px wide; App Store images are 16:10 (see `screenshot-plan.md`). "Help asset" is the image set name in the asset catalog. A cell with a dash means not used there.

| ID | Shows | Setup | Help asset | Website | Store |
|---|---|---|---|---|---|
| S-A1a | Register with the locked Deposit row | Checking account register, scroll to the first row | Help-opening-balance | features | – |
| S-A1b | Edit Details with the opening balance | Account edit sheet | Help-opening-balance-edit | – | – |
| S-A2 | Side panel with Primary Checking pinned | Whole sidebar | Help-sidebar | – | – |
| S-A3 | Routing fields on a checking account | Account edit sheet, routing section | Help-routing | – | – |
| S-A4a | Credit card details with the Goal section | Sapphire Card | Help-card-details | gallery | yes |
| S-A4b | Loan details with the Goal section | Student Loan | Help-loan-details | gallery | yes |
| S-A4c | Savings details with the Goal section | House Down Payment | Help-savings-details | gallery | yes |
| S-A5 | Cash on Hand with the New Cash Transaction button | Cash on Hand page | Help-cash-page | – | – |
| S-A6 | Whole window with the colored side panel and status bar | Summary | Help-welcome | hero | yes |
| S-B1 | Register with the three status colors | Checking register | Help-register | features | yes |
| S-B2 | Edit Transaction sheet with receipt | Right-click ▸ Edit Transaction | Help-edit-transaction | – | – |
| S-B3 | New Transaction with autofilled payee | Type "Bean There Coffee" | Help-autofill | features | – |
| S-B4a | Export sheet | Account page ▸ Print PDF | Help-export | features | yes |
| S-B4b | A page of the PDF in Preview | Open the saved PDF | Help-pdf | features | – |
| S-B4c | Account page toolbar (Import CSV, Export CSV, Print PDF) | Any account | Help-account-toolbar | – | – |
| S-B5a | Import preview with counts | Import Statement with a sample file | Help-import | features | yes |
| S-B5b | How this file is read (mapping) | Same sheet, section open | Help-import-mapping | features | – |
| S-B5c | Import result with Undo | After importing | Help-import-result | – | – |
| S-B5d | Saved format name field | Save Format | Help-import-format | – | – |
| S-B6a | Clean Up find and replace | Settings ▸ Clean Up | Help-cleanup | features | – |
| S-B6b | Look-alike payees | Same tab | Help-cleanup-payees | – | – |
| S-B6c | Move a category's transactions | Same tab | Help-cleanup-category | – | – |
| S-B7 | Budget editor with "Counts as tax-related" | Settings ▸ Categories | Help-tax | – | – |
| S-B8a | Split editor | New Transaction ▸ Split | Help-split | features | yes |
| S-B8b | Register row "Split (3)" | Register | Help-split-register | – | – |
| S-B8c | Detail window listing the parts | Double-click | Help-split-detail | – | – |
| S-B9a | Tag picker | Edit Transaction | Help-tags | features | – |
| S-B9b | Register with tag chips | Register | Help-tags-register | – | – |
| S-B9d | Tags settings | Settings ▸ Tags | Help-tags-settings | – | – |
| S-B10a | Recurring rules screen | Bills & Recurring ▸ Recurring tab | Help-recurring | features | yes |
| S-B10b | Rule editor | Add a rule | Help-recurring-edit | – | – |
| S-B10c | Pending entry made by a rule | Register | Help-recurring-pending | – | – |
| S-C1 | Summary with Priority Bills | Summary | Help-priority-bills | features | yes |
| S-C2 | Menu bar pop-up | Click the menu bar item | Help-menu-bar | features | – |
| S-C3a | The widget on the desktop, three sizes | Desktop (owner takes this) | Help-widgets | features | yes |
| S-C3b | Widget gallery | Edit widgets (owner takes this) | Help-widget-gallery | – | – |
| S-C3c | Edit Widget choices | Right-click a widget (owner takes this) | Help-widget-choices | – | – |
| S-D1a | Goal editor with the account link | Planning ▸ New Goal | Help-goal-edit | features | – |
| S-D1b | Goal section close-up | Any linked account | Help-goal-section | features | – |
| S-D1c | Planning page | Planning | Help-goals | gallery | yes |
| S-D2 | Planning with loans and estimated dates | Planning, lower area | Help-planning-loans | – | – |
| S-D3 | Budgets page | Overview ▸ Budgets | Help-budgets | features | – |
| S-E1a | A report with a projection | Reports ▸ Spending or Net Worth | Help-reports | gallery | yes |
| S-E1b | Period button open | Reports | Help-reports-period | – | – |
| S-E1c | Empty card with "needs more data" | Wipe, then Reports | Help-reports-empty | – | – |
| S-E2a | Summary, top | Summary | Help-summary | hero | yes |
| S-E2b | Summary, lower | Scroll down | Help-summary-lower | gallery | – |
| S-E3a | Liabilities | Liabilities | Help-liabilities | gallery | yes |
| S-E3b | Investments | Investments | Help-investments | gallery | yes |
| S-F2 | Data & Backup settings | Settings ▸ Data & Backup | Help-backup | – | – |
| S-F3 | Finder: Backups ▸ Before this update | Dropped: no picture, the text explains it | – | – | – |
| S-G1 | The Help window | Help ▸ Oinkly Budget Help | Help-window | – | – |
| S-G2 | Keyboard shortcuts topic | Help | Help-shortcuts | – | – |
| S-G3 | Export defaults | Settings | Help-export-defaults | – | – |

Also retake the earlier Help shots that stay: Help-atm-withdrawal, Help-card-charge, Help-receipt, Help-bills, Help-new-bill, Help-pay-bill, Help-categories, Help-manage-accounts, Help-sidebar.

## Rules for keeping this list true

- Add a row here the moment a feature is built or changed. The four documents follow this file.
- When a screen changes after its screenshot is taken, retake the screenshot.
- Shots marked "owner takes this" need panels or other apps Claude can't drive.

## Naming note

The Bills page is now called **Bills & Recurring** (sidebar, page title, status bar and the reminder page chooser). It has two tabs: Bills and Recurring. Use that name everywhere in Help, screenshots, the website and the release notes. Where those documents say "the Bills page" for the calendar and bill list, it is the Bills tab of Bills & Recurring.
