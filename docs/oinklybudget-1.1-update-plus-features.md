# OinklyBudget 1.1: update plus features

Drafted 2026-10-16. Nothing here is started. Version 1.0 is in App Review and does not change.

## Goal

Make the Mac app more useful for people who keep their books on paper and PDF. 1.1 adds printing and PDF export across the app, a few more reports, and some everyday Quicken-style features. The direction stays the same: a full desktop program, no bank linking, no accounts, no network.

## What is already there

Registers, transfers, bills and bill pay, budgets, goals, investments and liabilities, reports and top spending, reconcile, search, receipts, custom reminders, CSV import and export, `.pig` backup and restore, Help, release notes. There is no printing and no PDF output yet.

## Must have: printing and PDF

| Feature | Notes |
|---|---|
| **Print a register** | An account's transactions for a date range, with running balance. Print or Save as PDF. |
| **Print a transaction** | One transaction with its details and receipt. |
| **Print reports** | Every report and the spending charts: Print and Save as PDF from the report window. |
| **Print the budget** | Budget versus actual for a month or year. |
| **Print bills** | Upcoming and paid bills, as a list or a calendar. |
| **Net worth and account summary** | One-page statement of accounts and balances at a date. |
| **Page setup** | Paper size, orientation, margins, header and footer (title, date, page numbers). |
| **File ▸ Print… (⌘P)** and **File ▸ Export as PDF…** | Work from the front window, with a preview. |

How to build it so each screen does not need its own printing code:

- Make each printable thing a SwiftUI "report page" view that takes its data and a paper size.
- Render pages with `ImageRenderer` into PDF, with page breaks for long lists. Keep headers repeating on each page.
- Print through the standard Mac print panel (`NSPrintOperation` over the PDF), and use the same PDF for Save as PDF.
- Use a shared set of print styles (fonts, colours that print well in black and white, table lines).
- Test with long registers (thousands of rows) for speed and page breaks.

## Should have: reports and everyday features

Pick from this list; each one is small to medium.

- **More reports:** income and expense by category and by payee, monthly cash flow, net worth over time, year-end summary, tax-related category summary.
- **Report options:** date range presets, account and category filters, compare to last period, export the table as CSV.
- **Memorised and recurring transactions:** the register already learns payees; add scheduled repeats (paycheque, rent) with a reminder or auto-entry.
- **Split transactions:** one payment split across several categories.
- **Tags or labels** on transactions, usable in reports.
- **Find and replace** across payees and categories, plus a clean-up of duplicate payees.
- **Import from OFX and QIF files** that people download from their bank website. This is a manual file import, not a bank connection, so it fits the app's promise.
- **Check printing layout** (optional): print checks on standard check stock.

## Nice to have

- Attachments beyond receipts (PDF statements kept with an account).
- Keyboard shortcuts review and more menu commands.
- Accessibility pass (VoiceOver, larger text) for the new screens.
- Settings for default report period and print style.

## Data file work (not in 1.1)

Letting people choose where the data file is saved, with one shared file on one Mac opened by one person at a time, is a separate and bigger change. It is not part of 1.1. Until it is planned, avoid new code that assumes the data lives in a fixed place. The earlier plan is in git history (`docs/data-file-plan.md`).

## Order of work

1. **Printing foundation:** shared report page, page setup, Print and Save as PDF commands. Prove it on the register.
2. **Print everywhere:** transaction, budget, bills, reports.
3. **New reports** and report options.
4. **Everyday features:** pick two or three from "Should have" (recurring, splits and OFX/QIF import are the strongest).
5. **Polish:** Help pages and screenshots for every new feature, release notes, accessibility check.
6. **Release:** TestFlight, submission, website and listing update.

## Rough effort

| Part | Effort |
|---|---|
| Printing foundation and register | 1 to 2 weeks |
| Print for the other screens | 1 week |
| New reports and options | 1 to 2 weeks |
| Each everyday feature | 3 days to 2 weeks (splits and recurring are the larger ones) |
| Help, screenshots, release | 1 week |

About 5 to 8 weeks part-time for printing, reports and two or three everyday features.

## Release housekeeping

- Version 1.1, build number up by one for every upload. Keep the schema at `PiggybankSchemaV1` unless a feature needs a model change (splits, tags and recurring transactions do). If so, add `PiggybankSchemaV2` with a tested migration, and test with a copy of real data first.
- Backup before updating: remind users in the release notes.
- New screenshots for the listing and Help for the new features.
- Update the website product page and the "What's new" text.
- Remove the unused iCloud and push entitlements before the next upload.

## Risks

- **Print quality:** long lists, page breaks and different paper sizes. Test on real printers and PDF.
- **Model changes** for splits, tags and recurring transactions need a migration. Keep them small and tested.
- **Scope:** printing alone is worth shipping. Stop adding features when the schedule slips.
- **Review:** the new version goes through App Review again. Keep release notes clear and the app free of crashes.

## Decisions needed

1. Which of the "Should have" features come in 1.1 (suggestion: recurring transactions, split transactions, OFX/QIF import)?
2. Are check printing and attachments in or out?
3. Is any model change acceptable in 1.1, or should it be print and report features only?
4. Release timing, after 1.0 is approved?
