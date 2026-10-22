# Help file plan for 1.0

Drafted 2026-10-18. Help is written last (step 6 of the final plan) so it describes the finished app. This file says what to write, in what order, and how to check it.

## How Help works today

- Help is one Swift file, `Views/HelpWindow.swift`. `HelpContent.groups` holds groups of topics. Each topic has a title, an SF Symbol, a list of lines and optional screenshots (`Shot(asset:caption:)`).
- Line styles: `## Heading`, `• bullet`, plain text.
- A screenshot shows under a topic when an image set with the exact name exists in `Assets.xcassets`. A missing image just doesn't show.
- Search at the top of the list matches topics. Opens with ⇧⌘/ or Help ▸ Oinkly Budget Help. The window now opens at 1100×780.
- The groups at the start of the project were: Start Here, Accounts, Everyday Money, Bills, Planning & Reports, Data & Settings, Reference.

## Rules for writing it

- Describe the finished 1.0 app only. No "coming soon", and no mention of earlier builds.
- Plain words, short lines, one idea per bullet. Say where to click (menu path or page name).
- Every locked field gets a line in "Why Can't I Change That?" (new locked things in 1.0: opening Deposit, bill-payment categories, split totals).
- Say the honest limits: encryption protects the file at rest, a forgotten passphrase with no recovery key cannot be recovered, shared file is one person at a time.
- No financial figures from the owner's real data. Use the test data set only.

## Every feature gets a topic, and every topic explains how it works

The master list is `feature-master-list-1.0.md`. Each feature there (A1 to G3) must appear in Help. A topic is not finished until it has all of these:

1. **What it is**, in one or two sentences.
2. **How it works**, step by step: where to click (menu path or page), what each field or button does, and what happens next. The "How it works" bullets in the master list are the starting text; add steps and examples.
3. **The rules and limits**: what is locked and why, what can't be done, what is not protected (encryption), what can't be undone.
4. **An example** with real-looking numbers from the test data.
5. **A screenshot** for each screen the text describes (asset names in the master list's shot register). A topic about a dialog shows the dialog.
6. **Related topics** by name, so people can follow on.

Topics for planned features are written only if the feature ships.

### Topic map (master list section to Help topic)

| Master list | Help group | Help topic | Edit or new |
|---|---|---|---|
| A1 Opening balance | Accounts | Opening Balances | new |
| A2 Primary checking | Accounts | Adding & Managing Accounts (section: Primary Checking) | edit |
| A3 Routing numbers | Accounts | Adding & Managing Accounts (section: Routing Numbers) | edit |
| A4 Details and Goal section | Accounts | Credit Cards, Loans & Mortgages, plus a new Savings & Checking Accounts topic | edit and new |
| A5 Cash on Hand button | Accounts | Cash on Hand | edit |
| A6 Side panel and shell | Start Here | Finding Your Way | edit |
| B1 Status colors | Everyday Money | Transactions & Registers (section: Statuses) | edit |
| B2 Edit Transaction | Everyday Money | Transactions & Registers (section: Editing) | edit |
| B3 Autofill | Everyday Money | Autofill | new |
| B4 Export and print | Exporting & Printing | Export to PDF and CSV | new |
| B5 Import Statement | Exporting & Printing | Importing a Statement (with a worked example and a "Column mapping" subtopic) | new |
| B6 Clean Up | Data & Settings | Clean Up (three subtopics: payees, look-alikes, categories) | new |
| B7 Tax-related | Planning & Reports | Categories & Budgets (section: Tax-Related) | edit |
| B8 Splits | Everyday Money | Split Transactions | new, if built |
| B9 Tags | Everyday Money | Tags | new, if built |
| B10 Recurring | Everyday Money | Recurring Transactions | new, if built |
| C1 Priority Bills | Bills | The Bills Page (section: Priority Bills on the Summary) | edit |
| C2 Menu bar | Data & Settings | Menu Bar & Reminders | edit |
| C3 Widgets | Data & Settings | Widgets | new |
| D1 Goals follow accounts | Planning & Reports | Goals (rewritten: linking, statuses, pace, catch up, estimated finish, creating an account from a goal) | edit |
| D2 Planning page | Planning & Reports | Goals (section: Loans and Estimated Dates) | edit |
| D3 Budgets page | Planning & Reports | Categories & Budgets (section: The Budgets Page) | edit |
| E1 Reports | Planning & Reports | Reports (period button, projections, empty cards) | edit |
| E2 Summary | Planning & Reports | Summary (each card explained) | edit |
| E3 Liabilities, Investments | Planning & Reports | Liabilities, Investments | edit |
| F2 Data & Backup | Data & Settings | Backup & Restore | edit |
| F3 Safe update | Data & Settings | Updating to 1.0 (the safety copy, where it is, deleting it) | new |
| F4 Shared file | Data & Settings | Sharing One Data File | new, if built |
| G1 Windows | Start Here | Welcome (mention Help and Release Notes) | edit |
| G2 Shortcuts, accessibility | Reference | Keyboard Shortcuts, Accessibility | edit and new |
| G3 Export defaults | Exporting & Printing | Export to PDF and CSV (section) | edit, if built |

Also update, always: Welcome (first-minutes list), Settings (new tab list: General, Reminders, Accounts, Categories, Clean Up, Payment Methods, Data & Backup), Why Can't I Change That? (locked opening Deposit, locked split totals *(if built)*, a goal-linked account's goal), and Your Data & Privacy (encryption, shared file, widgets, safety copy).

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
