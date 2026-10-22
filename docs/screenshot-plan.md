# Screenshot plan for 1.0

Drafted 2026-10-18. Two sets: the screenshots inside Help, and the App Store screenshots. Both are taken last, from the test data, once the app is finished.

## Status (2026-10-21)

All the screenshots are taken, by the app itself, from the test data: about 80 raw pictures covering every page, account
type, window, sheet and Settings tab, the menu bar pop-up and the three widget sizes. `help-screenshots.md` says how to
retake them, and `scripts/make-help-images.py` turns them into the 70 Help images, the website pictures and the ten
App Store pictures. Only four things are left for the owner (see the end of `help-screenshots.md`).

## Rules for both sets

- The pictures are taken from a throwaway data file filled with the test data (`-screenshotMode`). Never fill the real
  data with test data.
- Light mode, a 1600 x 1000 window, no Testing menu.
- No real names, account numbers or balances. The test data is made up.
- Names are the asset names in the tables below.
- Retake everything whenever a screen changes.

## A. Help screenshots

Every new or changed feature has a Help screenshot, so each topic can show what the text describes. The shot register in `feature-master-list-1.0.md` is the master (it also says which shots the website and the App Store use). The register has 66 shots; this is the same list from the Help side. Asset names go into `Assets.xcassets` as image sets, named exactly as shown.

| ID | Help asset | Shows | Setup |
|---|---|---|---|
| S-A1a | `Help-opening-balance` | Register with the locked Deposit row | Checking account register, scroll to the first row |
| S-A1b | `Help-opening-balance-edit` | Edit Details with the opening balance | Account edit sheet |
| S-A2 | `Help-sidebar` | Side panel with Primary Checking pinned | Whole sidebar |
| S-A3 | `Help-routing` | Routing fields on a checking account | Account edit sheet, routing section |
| S-A4a | `Help-card-details` | Credit card details with the Goal section | Sapphire Card |
| S-A4b | `Help-loan-details` | Loan details with the Goal section | Student Loan |
| S-A4c | `Help-savings-details` | Savings details with the Goal section | House Down Payment |
| S-A5 | `Help-cash-page` | Cash on Hand with the New Cash Transaction button | Cash on Hand page |
| S-A6 | `Help-welcome` | Whole window with the colored side panel and status bar | Summary |
| S-B1 | `Help-register` | Register with the three status colors | Checking register |
| S-B2 | `Help-edit-transaction` | Edit Transaction sheet with receipt | Right-click ▸ Edit Transaction |
| S-B3 | `Help-autofill` | New Transaction with autofilled payee | Type "Bean There Coffee" |
| S-B4a | `Help-export` | Export sheet | Account page ▸ Print PDF |
| S-B4b | `Help-pdf` | A page of the PDF in Preview | Open the saved PDF |
| S-B4c | `Help-account-toolbar` | Account page toolbar (Import CSV, Export CSV, Print PDF) | Any account |
| S-B5a | `Help-import` | Import preview with counts | Import Statement with a sample file |
| S-B5b | `Help-import-mapping` | How this file is read (mapping) | Same sheet, section open |
| S-B5c | `Help-import-result` | Import result with Undo | After importing |
| S-B5d | `Help-import-format` | Saved format name field | Save Format |
| S-B6a | `Help-cleanup` | Clean Up find and replace | Settings ▸ Clean Up |
| S-B6b | `Help-cleanup-payees` | Look-alike payees | Same tab |
| S-B6c | `Help-cleanup-category` | Move a category's transactions | Same tab |
| S-B7 | `Help-tax` | Budget editor with "Counts as tax-related" | Settings ▸ Categories |
| S-B8a | `Help-split` | Split editor | New Transaction ▸ Split |
| S-B8b | `Help-split-register` | Register row "Split (3)" | Register |
| S-B8c | `Help-split-detail` | Detail window listing the parts | Double-click |
| S-B9a | `Help-tags` | Tag picker | Edit Transaction |
| S-B9b | `Help-tags-register` | Register with tag chips | Register |
| S-B9d | `Help-tags-settings` | Tags settings | Settings ▸ Tags |
| S-B10a | `Help-recurring` | Recurring rules screen | Bills & Recurring ▸ Recurring tab |
| S-B10b | `Help-recurring-edit` | Rule editor | Add a rule |
| S-B10c | `Help-recurring-pending` | Pending entry made by a rule | Register |
| S-C1 | `Help-priority-bills` | Summary with Priority Bills | Summary |
| S-C2 | `Help-menu-bar` | Menu bar pop-up | Click the menu bar item |
| S-C3a | `Help-widgets` | The widget on the desktop, small, medium and large | Desktop (owner takes this) |
| S-C3b | `Help-widget-gallery` | Widget gallery | Edit widgets (owner takes this) |
| S-D1a | `Help-goal-edit` | Goal editor with the account link | Planning ▸ New Goal |
| S-D1b | `Help-goal-section` | Goal section close-up | Any linked account |
| S-D1c | `Help-goals` | Planning page | Planning |
| S-D2 | `Help-planning-loans` | Planning with loans and estimated dates | Planning, lower area |
| S-D3 | `Help-budgets` | Budgets page | Overview ▸ Budgets |
| S-E1a | `Help-reports` | A report with a projection | Reports ▸ Spending or Net Worth |
| S-E1b | `Help-reports-period` | Period button open | Reports |
| S-E1c | `Help-reports-empty` | Empty card with "needs more data" | Wipe, then Reports |
| S-E2a | `Help-summary` | Summary, top | Summary |
| S-E2b | `Help-summary-lower` | Summary, lower | Scroll down |
| S-E3a | `Help-liabilities` | Liabilities | Liabilities |
| S-E3b | `Help-investments` | Investments | Investments |
| S-F2 | `Help-backup` | Data & Backup settings | Settings ▸ Data & Backup |
| S-F3 | (dropped) | Finder: Backups ▸ Before this update | No picture; the Help text explains it |
| S-G1 | `Help-window` | The Help window | Help ▸ Oinkly Budget Help |
| S-G2 | `Help-shortcuts` | Keyboard shortcuts topic | Help |
| S-G3 | `Help-export-defaults` | Export defaults | Settings |


The earlier shots that stay and are retaken: Help-atm-withdrawal, Help-card-charge, Help-receipt, Help-bills, Help-new-bill, Help-pay-bill, Help-categories, Help-manage-accounts, Help-sidebar.

Most useful: Help-welcome, Help-register, Help-pay-bill, Help-bills, Help-summary, Help-goal-section, Help-import.

## B. App Store screenshots

- Mac App Store wants 16:10 images. Accepted sizes: 1280×800, 1440×900, 2560×1600 or 2880×1800. Take them at 2880×1800 (or the largest the display gives) and scale down only if needed. Confirm the current size list in App Store Connect before exporting.
- Up to 10. The earlier set was 10 shots: summary, transactions, reports, liabilities, investments, bills, planning, checking, card, mortgage. Retake all 10 and replace any that no longer represent the app.
- Order that sells the app: Summary, Reports, Account with a goal, Bills, Planning, Investments, Liabilities, a Register, Export or Import, Widgets.
- Optional captions on each: one short line (for example "Know where your money goes" or "Your data stays on your Mac").
- The App Store takes at most 10, so choose 10 from the shots marked "yes" in the register (candidates: S-A4a, S-A4b, S-A4c, S-A6, S-B1, S-B4a, S-B5a, S-B8a, S-B10a, S-C1, S-C3a, S-D1c, S-E1a, S-E2a, S-E3a, S-E3b). Pick the ones that show the biggest new features: Summary, a Goal section, Reports, Import, Widgets, Export, Recurring or Splits if built, Liabilities, Investments.
- Keep the window title and the sidebar the same in every shot so the set looks uniform.

## Order of work

1. Finish the app (steps 2 to 5 of the final plan).
2. Wipe and fill test data, set light mode and the fixed window size.
3. Take the App Store set first, then the Help set.
4. Add the Help images to the asset catalog and confirm each topic shows its picture.
5. Review every shot at full size for stray details (real names, odd dates, empty placeholders).

## Hands-on parts only the owner can do

Widgets on the desktop, the menu bar pop-up, and any screen that needs a save or open panel cannot be captured by Claude, so the owner takes those.
