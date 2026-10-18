# Help file plan for 1.1

Drafted 2026-10-18. Help is written last (step 6 of the final plan) so it describes the finished app. This file says what to write, in what order, and how to check it.

## How Help works today

- Help is one Swift file, `Views/HelpWindow.swift`. `HelpContent.groups` holds groups of topics. Each topic has a title, an SF Symbol, a list of lines and optional screenshots (`Shot(asset:caption:)`).
- Line styles: `## Heading`, `• bullet`, plain text.
- A screenshot shows under a topic when an image set with the exact name exists in `Assets.xcassets`. A missing image just doesn't show.
- Search at the top of the list matches topics. Opens with ⇧⌘/ or Help ▸ OinklyBudget Help. The window now opens at 1100×780.
- 1.0 groups: Start Here, Accounts, Everyday Money, Bills, Planning & Reports, Data & Settings, Reference.

## Rules for writing it

- Describe the finished 1.1 app only. No "coming soon", no mention of 1.0 differences (those go in release notes).
- Plain words, short lines, one idea per bullet. Say where to click (menu path or page name).
- Every locked field gets a line in "Why Can't I Change That?" (new locked things in 1.1: opening Deposit, bill-payment categories, split totals).
- Say the honest limits: encryption protects the file at rest, a forgotten passphrase with no recovery key cannot be recovered, shared file is one person at a time.
- No financial figures from the owner's real data. Use the test data set only.

## Topic list

Existing topics that need edits are marked **edit**. New topics are marked **new**. Topics for features not yet built are marked *(if built)*; delete them if the feature is dropped.

| Group | Topic | Change | What to cover |
|---|---|---|---|
| Start Here | Welcome | edit | New first-minutes list (accounts, a first transaction, bills, goals), mention Clean Up and autofill |
| Start Here | Finding Your Way | edit | Locked sidebar, Budgets in Overview, Planning, account folders and colours |
| Accounts | Adding & Managing Accounts | edit | Opening balance becomes a locked Deposit, primary checking, routing numbers (ACH, wire may contain letters, digital), savings goal that creates an account |
| Accounts | Opening Balances | **new** | Why the opening Deposit is locked, how to change the amount, which accounts have one |
| Accounts | Cash on Hand | edit | New Cash Transaction button now lives on the Cash on Hand page |
| Accounts | Credit Cards, Loans & Mortgages | edit | New account details layout, the Goal section beside the details |
| Everyday Money | Transactions & Registers | edit | Status colours (green reconciled, yellow pending, red unreconciled), autofill memo and method from the last use of a payee |
| Everyday Money | Split Transactions | **new** *(if built)* | Splitting one payment across categories, the total must match, how it shows in the register and reports |
| Everyday Money | Tags | **new** *(if built)* | Adding tags, colours, filtering reports by tag |
| Everyday Money | Recurring Transactions | **new** *(if built)* | Making a rule, pending entries you confirm, the management screen, the forecast |
| Everyday Money | Receipts, Attachments | edit | Receipts as before; PDF statements kept with an account *(if built)* |
| Everyday Money | Transfers | keep | |
| Everyday Money | Importing a Statement | **new** | Import Statement on an account, preview, column mapping, saved mappings, duplicates, undo, with one worked example |
| Everyday Money | Clean Up | **new** | Find and replace for payees and categories, duplicate payees (Settings ▸ Clean Up) |
| Bills | The Bills Page, Paying a Bill | keep | Check wording against the app |
| Planning & Reports | Categories & Budgets | edit | Budgets page, zero budgets hidden, tax-related toggle, where to edit budgets (Settings) |
| Planning & Reports | Summary | edit | Reworked net worth and summary cards, line charts with projections |
| Planning & Reports | Reports | edit | Period button instead of tabs, six-month projections, placeholders that say "needs more data" |
| Planning & Reports | Goals | edit | Linking a goal to an account, savings and payoff goals, target dates, pace, catch-up, estimated finish |
| Planning & Reports | Liabilities, Investments | edit | Projections and growth cards |
| Exporting & Printing | Export to PDF and CSV | **new** | Every account, the Transactions page, Reports and Summary PDFs, paper size and style settings, how to print (open the PDF in Preview) |
| Exporting & Printing | Printing Checks | **new** *(if built)* | |
| Data & Settings | Backup & Restore | edit | `.pig` files, encrypted backups, where the automatic safety copy is (Application Support/Backups/Before 1.1) and that it can be deleted |
| Data & Settings | Encryption | **new** | Turning it on, passphrase, recovery key, remember on this Mac, the honest limits, no recovery without the key |
| Data & Settings | Sharing One Data File | **new** *(if built)* | Two Mac logins, one at a time, choose folder, who has it, close the file, take over a stale lock, what happens after a crash |
| Data & Settings | Widgets | **new** | Adding the bills and reminders widgets, what they show (no amounts), refreshing |
| Data & Settings | Menu Bar & Reminders | edit | Check against the app |
| Data & Settings | Settings | edit | New tabs (Clean Up, Data), updated list |
| Reference | Keyboard Shortcuts | edit | Rebuilt from the shortcut review (step 3) |
| Reference | Accessibility | **new** | VoiceOver and larger text notes from step 3 |
| Reference | Why Can't I Change That? | edit | Add the new locked things |
| Reference | Your Data & Privacy | edit | Add encryption and the shared file |

## Order of writing

1. Write topics for features as each one is finished, as plain notes in this file's table (what the screen does, the exact button names). Do not leave this to the end.
2. When step 5 lands (shared file), write the final topics.
3. In step 6: write all topics in `HelpWindow.swift`, then add screenshots (see `screenshot-plan.md`).
4. Read every topic aloud against the running app and fix wording that doesn't match a button.

## Checks before release

- Every menu path and button name in Help exists in the app (search the Swift files for the text).
- Every screenshot name in `Shot(...)` has an image set; no stale image shows an old screen.
- Search finds each new topic by its obvious words (import, split, tag, encrypt, widget, share, PDF).
- Help window is readable at the default size and at the smallest size.
- Dark mode: Help text and screenshots read fine.
