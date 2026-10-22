# Website update plan for the 1.0 release

Drafted 2026-10-18. The site is a small static site in `website-vaultstudio/website/` (no build step, upload the folder as it is). This plan says what changes when 1.0 ships, page by page, what new pages to add, what the text must say, and how to keep it honest. Nothing here is started.

## When

- Write the new text and take the new screenshots during step 6 of the final plan, when the app is finished. Draft the text earlier as features land, in this file or in `help-file-plan.md`.
- Publish the site **the same day the app goes live**, not before. Until then the product pages keep saying "Coming soon".
- This is the first public release (version 1.0, build 5), so the website describes it as the launch: no "update" wording and no "what's new since" text.

## Rules for the text

- **Keep it honest.** Every claim must be true of the shipped build. Check each sentence against the app before publishing.
- **Say the limits plainly:** there is no sync between devices, no bank linking, and a backup file is how data moves between computers.
- Plain words, short sentences, no sales language, no comparison with other apps.
- Privacy statements here, the App Privacy answers in App Store Connect and `PrivacyInfo.xcprivacy` must always agree.

## Page by page

### `oinklybudget.html` (product page): biggest change

| Section | Change |
|---|---|
| Headline and badge | Keep the one-line promise. Swap "Coming soon" for the App Store button when live. Confirm the price line ($9.99 one-time, no subscription) is still correct. |
| What it does (feature grid) | Rewrite as the finished app. Add the new features below. |
| Old school on purpose | Keep. Update the CSV sentence: Import Statement with preview, column mapping, saved mappings, duplicate skipping and undo. Still no bank linking. |
| Private by design | Add the local-only widgets. Keep "no accounts, no servers, no tracking". |
| A closer look | All screenshots retaken (see below), plus new ones. |
| Good to know | Update: still no sync between devices; backup file moves data between computers. |
| Requirements | Check the macOS minimum against the project setting before writing it. |

**Feature blocks to write.** The complete, detailed feature list is `feature-master-list-1.0.md`; every feature in it that is built appears on this page, with its screenshot from the table below. (a short heading, two or three sentences and a screenshot each):

1. **Goals that follow your accounts.** Savings and payoff goals tied to an account, with target date, status, monthly amount needed, pace and an estimated finish, in a Goal section on each account.
2. **Reports and projections.** One period button, line charts, six-month projections on reports, Liabilities and Investments, and a reworked Summary with net worth over time.
3. **Priority bills on the Summary.** The next five important bills due within 20 days.
4. **Budgets page** for every category with a budget.
5. **Split transactions**.* One payment across categories.
6. **Tags**.* Label transactions.
7. **Recurring transactions**.* Rules that make pending entries for you to confirm, and a cash flow forecast.
8. **Export to PDF and CSV.** Every account and the Transactions page. Print by opening the PDF.
9. **Import a statement.** Preview, map the columns, skip duplicates, undo.
10. **Clean Up and autofill.** Find and replace payees and categories, merge duplicates, memory for payee, category, memo and payment method.
11. **Widgets.** One Upcoming Transactions widget (small, medium, large) with bills, repeating transactions and reminders, no amounts or account details.
12. **Safe updates.** An automatic safety copy of your data before the first open in the new version.
13. **The basics** stay in the base list: accounts, bills, receipts, reminders, backups, menu bar item.

### `privacy.html`: must be updated

- New "Last updated" date.
- **Widgets:** the widgets read a small file on your Mac with bill names, reminder titles and dates only. No amounts, no account details, nothing leaves the Mac.
- **Safety copy:** the app keeps a copy of your data in its own folder when you update, until you delete it.
- **Files:** the app keeps receipt photos and PDF bills on transactions and nothing else. Say so where the privacy page describes photos and files.
- Keep "collects nothing", "no network" and "no analytics". If anything in 1.0 ever changes these, stop and fix the plan before publishing.
- Re-check `PrivacyInfo.xcprivacy` and the App Privacy answers in App Store Connect against this page.

### `support.html`: add questions

- What is the "Before this update" copy in Application Support ▸ Backups, and can I delete it? (yes, once you are happy)
- How do I import a statement and map the columns?
- How do I export a PDF, and how do I print it? (open it in Preview)
- How do I set up a goal that follows an account?
- How do I add widgets?
- How do I split a transaction, add a tag or make a recurring rule?
- Update: "Can I import transactions from my bank?" (CSV only, now with preview and mapping); "Does it sync?" (no; a backup file moves data between computers).
- Add a "Before you update" note: save a `.pig` backup first.

### `index.html` (home)

- Swap the "Coming soon for Mac" badge for "Now available for Mac" and add the App Store link when live.
- Update the one-line description on the Oinkly Budget card.

### `about.html`

- No change needed unless the studio description changes.

### New pages (recommended)

| Page | Why | Content |
|---|---|---|
| `whats-new.html` (optional) | A first-release page is not needed. Later releases add it, and the App Store "What's New" points to it | Release notes for each version in plain language, copied from the in-app notes (see `release-notes-1.0.md`) |
| `help.html` (optional) | The in-app Help on the web, searchable | Generated from the same text as `help-file-plan.md`. Only if time allows. |

Add any new page to the nav in the header and footer of every page, to `sitemap.xml`, and to the README table.

### Files that go with the pages

- `sitemap.xml`: add new pages, update `lastmod` dates.
- `style.css`: only if the new pages need layout the current styles lack (feature rows, comparison tables).
- `README.md` (website folder): update the table of files and the "Still to do before publishing" list.
- `images/`: replace every screenshot with the 1.0 ones; keep 1600 px wide, light mode, from the test data; new names as needed (goal section, priority bills, import preview, export sheet, encryption settings, widgets, split, tags, recurring). Add `og:image` and a favicon at several sizes while there.

## Screenshots for the website

Every new feature gets at least one picture on the product page, and the key ones are also in the gallery. The full list of every screenshot (with setup steps) is the shot register in `feature-master-list-1.0.md`; this is the part the website uses. Images are 1600 px wide, light mode, from the test data, and compressed (optimised PNG or WebP). Every image needs alt text that describes what it shows. File names below are suggested.

"features" means the image sits beside that feature's block on the product page. "gallery" means it is in the "A closer look" gallery (click to enlarge). "hero" means it is a large picture at the top of the page or on the home page.

| ID | Shows | File | Where on the site |
|---|---|---|---|
| S-A1a | Register with the locked Deposit row | `web-opening-balance.png` | features |
| S-A4a | Credit card details with the Goal section | `web-card-details.png` | gallery |
| S-A4b | Loan details with the Goal section | `web-loan-details.png` | gallery |
| S-A4c | Savings details with the Goal section | `web-savings-details.png` | gallery |
| S-A6 | Whole window with the colored side panel and status bar | `web-welcome.png` | hero |
| S-B1 | Register with the three status colors | `web-register.png` | features |
| S-B3 | New Transaction with autofilled payee | `web-autofill.png` | features |
| S-B4a | Export sheet | `web-export.png` | features |
| S-B4b | A page of the PDF in Preview | `web-pdf.png` | features |
| S-B5a | Import preview with counts | `web-import.png` | features |
| S-B5b | How this file is read (mapping) | `web-import-mapping.png` | features |
| S-B6a | Clean Up find and replace | `web-cleanup.png` | features |
| S-B8a | Split editor | `web-split.png` | features |
| S-B9a | Tag picker | `web-tags.png` | features |
| S-B10a | Recurring rules screen | `web-recurring.png` | features |
| S-C1 | Summary with Priority Bills | `web-priority-bills.png` | features |
| S-C2 | Menu bar pop-up | `web-menu-bar.png` | features |
| S-C3a | Both widgets on the desktop | `web-widgets.png` | features |
| S-D1a | Goal editor with the account link | `web-goal-edit.png` | features |
| S-D1b | Goal section close-up | `web-goal-section.png` | features |
| S-D1c | Planning page | `web-goals.png` | gallery |
| S-D3 | Budgets page | `web-budgets.png` | features |
| S-E1a | A report with a projection | `web-reports.png` | gallery |
| S-E2a | Summary, top | `web-summary.png` | hero |
| S-E2b | Summary, lower | `web-summary-lower.png` | gallery |
| S-E3a | Liabilities | `web-liabilities.png` | gallery |
| S-E3b | Investments | `web-investments.png` | gallery |

Also retake the existing gallery pictures that stay (Transactions, Bills, Register, Card, Mortgage, Reports, Liabilities, Investments, Planning, Summary), because the app's layout changed. Add `og:image` and favicon sizes while there.

Shots the owner must take (Claude cannot drive them): the widgets on the desktop, the widget gallery, the Finder Backups folder, and the second Mac login's window.

## Order of work

1. Draft the feature text as each feature is finished (keep notes in this file).
2. Take screenshots with the App Store and Help screenshots, in one session.
3. Write the pages in a copy of the site folder, not the live one.
4. Read every sentence against the shipped build.
5. Check privacy page, `PrivacyInfo.xcprivacy` and the App Privacy answers say the same thing.
6. Check links, images, dark mode, the phone-width layout and the hamburger menu.
7. Publish the same day the app is released. Swap "Coming soon" for the App Store link.
8. Set the support email forwarding if not done (`support@vaultstudio.dev`).

## Checks before publishing

- Every feature named on the site exists in the shipped build.
- Every limit is stated (no sync, no bank linking).
- No page promises a feature that is not in the app.
- Price, macOS version, app version and dates are right.
- Images load, have alt text and are the right size.
- Privacy policy, App Privacy answers and `PrivacyInfo.xcprivacy` agree.
- Support, Privacy and What's New URLs are the ones entered in App Store Connect.
- The App Store listing text and the site say the same thing.

## Open questions

1. ~~Is 1.0 the first public release, or an update to a released 1.0?~~ **Decided 2026-10-18:** the first public release, version 1.0, build 5.
2. Price: still $9.99 one-time?
3. Do you want the web Help page, or only the in-app Help?
4. A separate security page, or a section on the privacy page?
5. Who handles `support@vaultstudio.dev` forwarding before launch?
