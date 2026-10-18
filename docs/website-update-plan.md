# Website update plan for the 1.1 release

Drafted 2026-10-18. The site is a small static site in `website-vaultstudio/website/` (no build step, upload the folder as it is). This plan says what changes when 1.1 ships, page by page, what new pages to add, what the text must say, and how to keep it honest. Nothing here is started.

## When

- Write the new text and take the new screenshots during step 6 of the final plan, when the app is finished. Draft the text earlier as features land, in this file or in `help-file-plan.md`.
- Publish the site **the same day the app goes live**, not before. Until then the product pages keep saying "Coming soon".
- If 1.1 becomes the first public release (see the 1.0 / 1.1 discussion), the website describes it as the launch: no "update" wording, no "what's new since 1.0". If 1.0 is released first, the page describes 1.1 as the current version and a What's New page covers the change.

## Rules for the text

- **Keep it honest.** Every claim must be true of the shipped build. Check each sentence against the app before publishing.
- **Say the limits plainly:** encryption protects the data file at rest, a forgotten passphrase with no recovery key cannot be recovered, the shared data file is one person at a time and on one Mac, and there is still no sync between devices.
- Plain words, short sentences, no sales language, no comparison with other apps.
- Do not call the shared file "sync" or "cloud". It is one file shared between Mac logins on the same Mac.
- Privacy statements here, the App Privacy answers in App Store Connect and `PrivacyInfo.xcprivacy` must always agree.

## Page by page

### `oinklybudget.html` (product page): biggest change

| Section | Change |
|---|---|
| Headline and badge | Keep the one-line promise. Swap "Coming soon" for the App Store button when live. Confirm the price line ($9.99 one-time, no subscription) is still correct. |
| What it does (feature grid) | Rewrite as the finished app. Add the new features below. |
| Old school on purpose | Keep. Update the CSV sentence: Import Statement with preview, column mapping, saved mappings, duplicate skipping and undo. Still no bank linking. |
| Private by design | Add encryption, and the local-only widgets. Keep "no accounts, no servers, no tracking". |
| A closer look | All screenshots retaken (see below), plus new ones. |
| Good to know | Update: still no sync between devices; backup file moves data between computers; a shared data file lets two Mac logins on one Mac take turns. |
| Requirements | Check the macOS minimum against the project setting before writing it. |

**Feature blocks to write** (a short heading, two or three sentences and a screenshot each):

1. **Goals that follow your accounts.** Savings and payoff goals tied to an account, with target date, status, monthly amount needed, pace and an estimated finish, in a Goal section on each account.
2. **Reports and projections.** One period button, line charts, six-month projections on reports, Liabilities and Investments, and a reworked Summary with net worth over time.
3. **Priority bills on the Summary.** The next five important bills due within 20 days.
4. **Budgets page** for every category with a budget.
5. **Split transactions** *(if built).* One payment across categories.
6. **Tags** *(if built).* Label transactions and filter reports.
7. **Recurring transactions** *(if built).* Rules that make pending entries for you to confirm, and a cash flow forecast.
8. **Export to PDF and CSV.** Every account, the Transactions page, Reports and Summary *(if built)*. Print by opening the PDF.
9. **Import a statement.** Preview, map the columns, skip duplicates, undo.
10. **Clean Up and autofill.** Find and replace payees and categories, merge duplicates, memory for payee, category, memo and payment method.
11. **Encrypted data file.** Passphrase, recovery key, encrypted backups, remember on this Mac.
12. **Widgets.** Upcoming bills and reminders, no amounts or account details.
13. **Share one data file** *(if built).* Two Mac logins, one at a time, with who has it and when.
14. **Safe updates.** An automatic safety copy of your data before the first open in the new version.
15. **Everything else from 1.0** stays in the base list: accounts, bills, receipts, reminders, backups, menu bar item.

### `privacy.html`: must be updated

- New "Last updated" date.
- **Encryption:** add a section. The file can be encrypted with a passphrase you choose; we never see the passphrase or the key; backups use the same passphrase; a forgotten passphrase cannot be recovered without the recovery key.
- **Shared data file:** the file lives where you choose, on your Mac. Nothing is uploaded. Where you place it is your decision, and a cloud-synced folder is governed by that service's policy.
- **Widgets:** the widgets read a small file on your Mac with bill names, reminder titles and dates only. No amounts, no account details, nothing leaves the Mac.
- **Safety copy:** the app keeps a copy of your data in its own folder when you update, until you delete it.
- **Attachments:** update the photos and files text if PDF statements are kept with accounts.
- Keep "collects nothing", "no network" and "no analytics". If anything in 1.1 ever changes these, stop and fix the plan before publishing.
- Re-check `PrivacyInfo.xcprivacy` and the App Privacy answers in App Store Connect against this page.

### `support.html`: add questions

- How do I turn on encryption, and what if I forget the passphrase? (recovery key, no other way)
- How do I share one data file between two Mac logins? Step by step, with the take-over and "close file" instructions. *(if built)*
- What is the "Before 1.1" copy in Application Support ▸ Backups, and can I delete it? (yes, once you are happy)
- How do I import a statement and map the columns?
- How do I export a PDF, and how do I print it? (open it in Preview)
- How do I set up a goal that follows an account?
- How do I add widgets?
- How do I split a transaction, add a tag or make a recurring rule? *(if built)*
- Update: "Can I import transactions from my bank?" (CSV only, now with preview and mapping); "Does it sync?" (no; the shared file is one person at a time on one Mac).
- Add a "Before you update" note: save a `.pig` backup first.

### `index.html` (home)

- Swap the "Coming soon for Mac" badge for "Now available for Mac" and add the App Store link when live.
- Update the one-line description on the OinklyBudget card.

### `about.html`

- No change needed unless the studio description changes.

### New pages (recommended)

| Page | Why | Content |
|---|---|---|
| `whats-new.html` | The place the App Store "What's New" points to | Release notes for 1.1 in plain language, copied from the in-app notes (see `release-notes-1.1-draft.md`), and a "Before you update" box |
| `security.html` (or a section of `privacy.html`) | People will ask how the encryption works | What is protected and what is not, in plain words: protects the file at rest and in sharing, the working copy is unencrypted while the file is open, FileVault still matters, recovery key explained |
| `help.html` (optional) | The in-app Help on the web, searchable | Generated from the same text as `help-file-plan.md`. Only if time allows. |

Add any new page to the nav in the header and footer of every page, to `sitemap.xml`, and to the README table.

### Shared files

- `sitemap.xml`: add new pages, update `lastmod` dates.
- `style.css`: only if the new pages need layout the current styles lack (feature rows, comparison tables).
- `README.md` (website folder): update the table of files and the "Still to do before publishing" list.
- `images/`: replace every screenshot with the 1.1 ones; keep 1600 px wide, light mode, from the test data; new names as needed (goal section, priority bills, import preview, export sheet, encryption settings, widgets, split, tags, recurring). Add `og:image` and a favicon at several sizes while there.

## Screenshots for the website

Use the same test data and the same rules as `screenshot-plan.md`. The site wants about 14 to 18 images: Summary, Reports, a Goal section, Bills, Planning, Investments, Liabilities, Transactions, Register, Card, Mortgage, Import preview, Export sheet, Encryption settings, Widgets, and one each for splits, tags and recurring if built. Compress them (PNG optimised or WebP) so the product page stays fast.

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
- Every limit is stated (encryption, shared file, no sync).
- No page promises something marked "(if built)" that was dropped.
- Price, macOS version, app version and dates are right.
- Images load, have alt text and are the right size.
- Privacy policy, App Privacy answers and `PrivacyInfo.xcprivacy` agree.
- Support, Privacy and What's New URLs are the ones entered in App Store Connect.
- The App Store listing text and the site say the same thing.

## Open questions

1. Is 1.1 the first public release, or an update to a released 1.0? (changes the wording of every page)
2. Price: still $9.99 one-time?
3. Do you want the web Help page, or only the in-app Help?
4. A separate security page, or a section on the privacy page?
5. Who handles `support@vaultstudio.dev` forwarding before launch?
