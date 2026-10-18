# Screenshot plan for 1.1

Drafted 2026-10-18. Two sets: the screenshots inside Help, and the App Store screenshots. Both are taken last, from the test data, once the app is finished.

## Rules for both sets

- Use the debug-only Testing menu: OinklyBudget ▸ Testing ▸ Fill with Test Data. It replaces all data, so never do it on real data. Wipe and refill before each batch so every shot starts from the same data.
- Light mode for all of them (Settings ▸ General ▸ Interface ▸ Light), unless a shot is specifically about dark mode.
- Fixed window size for every shot. Take the whole window with ⇧⌘4, Space, click (Option-click leaves the shadow off).
- No real names, account numbers or balances. The test data is made up.
- Save as PNG. Name files exactly as in the tables.
- Retake every 1.0 Help shot, because the app's layout has changed (locked sidebar, new account details, new Summary and Reports).

## A. Help screenshots

Asset names go into `Assets.xcassets` as image sets. The 18 from 1.0 are all retaken. New ones are marked **new**.

| Asset name | Topic | What to show |
|---|---|---|
| Help-welcome | Welcome | Summary with test data, side panel visible |
| Help-sidebar | Finding Your Way | Side panel only, folders expanded |
| Help-manage-accounts | Adding & Managing Accounts | Settings ▸ Accounts with a few accounts |
| Help-opening-balance | Opening Balances **new** | A locked Deposit row in a register, and the account setup showing the opening balance |
| Help-atm-withdrawal | Cash on Hand | ATM Withdrawal window filled in |
| Help-cash-page | Cash on Hand **new** | Cash on Hand page with the New Cash Transaction button |
| Help-card-charge | Credit Cards | New Credit Card Charge with available credit showing |
| Help-card-details | Credit Cards | A credit card page with account details and the Goal section |
| Help-loan-details | Loans & Mortgages | A loan page with progress and the Goal section |
| Help-register | Transactions & Registers | Checking register with a month of transactions and the status colours |
| Help-edit-transaction | Transactions & Registers | Edit Transaction sheet |
| Help-split | Split Transactions **new** *(if built)* | A transaction split across three categories |
| Help-tags | Tags **new** *(if built)* | Tags on a transaction and the tag filter on a report |
| Help-recurring | Recurring Transactions **new** *(if built)* | The rules screen with three rules and one pending entry |
| Help-receipt | Receipts | Receipt sheet with a photo or PDF |
| Help-import | Importing a Statement **new** | The preview with new, duplicate and problem counts |
| Help-import-mapping | Importing a Statement **new** | The column mapping screen |
| Help-cleanup | Clean Up **new** | Settings ▸ Clean Up with a find and replace filled in |
| Help-bills | The Bills Page | Calendar, Important list, Add a Bill |
| Help-new-bill | The Bills Page | New Bill form with a category |
| Help-pay-bill | Paying a Bill | Pay a Bill filled in |
| Help-categories | Categories & Budgets | Settings ▸ Categories |
| Help-budgets | Categories & Budgets **new** | Budgets page with the note about editing in Settings |
| Help-summary | Summary **new** | The reworked Summary |
| Help-reports | Reports | Reports page with the period button and a projection chart |
| Help-goals | Goals | Planning page with a savings goal and a payoff goal |
| Help-goal-section | Goals **new** | An account's Goal section close up |
| Help-liabilities | Liabilities **new** | Liabilities page with projections |
| Help-investments | Investments **new** | Investments page with growth and projection cards |
| Help-export | Export to PDF and CSV **new** | The Export sheet |
| Help-backup | Backup & Restore | Settings ▸ Import & Export |
| Help-encryption | Encryption **new** | Settings encryption screen (no passphrase shown) |
| Help-shared-file | Sharing One Data File **new** *(if built)* | The shared file settings and a "someone else has this file" prompt |
| Help-widgets | Widgets **new** | The widgets on the desktop or in Notification Center |
| Help-menu-bar | Menu Bar & Reminders | The menu bar pop-up open |

Most useful: Help-welcome, Help-register, Help-pay-bill, Help-bills, Help-summary, Help-goal-section, Help-import.

## B. App Store screenshots

- Mac App Store wants 16:10 images. Accepted sizes: 1280×800, 1440×900, 2560×1600 or 2880×1800. Take them at 2880×1800 (or the largest the display gives) and scale down only if needed. Confirm the current size list in App Store Connect before exporting.
- Up to 10. The 1.0 set was 10 shots: summary, transactions, reports, liabilities, investments, bills, planning, checking, card, mortgage. Retake all 10 and replace any that no longer represent the app.
- Order that sells the app: Summary, Reports, Account with a goal, Bills, Planning, Investments, Liabilities, a Register, Export or Import, Widgets.
- Optional captions on each: one short line (for example "Know where your money goes" or "Your data stays on your Mac").
- Add a widget shot and an encryption or privacy shot, since they are new in 1.1.
- Keep the window title and the sidebar the same in every shot so the set looks uniform.

## Order of work

1. Finish the app (steps 2 to 5 of the final plan).
2. Wipe and fill test data, set light mode and the fixed window size.
3. Take the App Store set first, then the Help set.
4. Add the Help images to the asset catalog and confirm each topic shows its picture.
5. Review every shot at full size for stray details (real names, odd dates, empty placeholders).

## Hands-on parts only the owner can do

Widgets on the desktop, the menu bar pop-up, and any screen that needs a save or open panel cannot be captured by Claude, so the owner takes those.
