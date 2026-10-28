# Oinkly 1.1 Release Plan

**Build name:** Laser Focused, You Idiot

## Overview

Version 1.1 is mostly about the debt war plan, plus receipt verification, PDF letterhead, automatic updates (Sparkle), live holding prices, and general polish. In-app humor stays Mel Brooks inspired, mainly Spaceballs.

## Feature 1: Laser Focus Annihilation ✅ Done

- [x] Add a third mode to the debt war plan strategy selector, next to Snowball and Avalanche.
- [x] When Laser Focus Annihilation is selected, a dropdown appears for choosing the target debt (for example, a small debt that's annoying the user). It sits right beside the strategy buttons.
- [x] New debts are added to the dropdown automatically.
- [x] When the target debt is paid off, its payment rolls over to the next debt.
- [x] Bonus: the new **Savings War Plan** tab has the same Laser Focus Annihilation mode for savings accounts.

## Feature 2: Receipt Verification ✅ Done (first version)

- [x] Scan a receipt with Apple's Vision framework while entering a transaction (new transaction, credit card charge, cash transaction and edit). PDFs with text are read directly.
- [x] The scan checks the entered total, date and payee against the receipt and suggests corrections if they don't match. Nothing changes until the Use button is pressed.
- [x] Receipt learning stays on the device: the app remembers which payee goes with which store, in a small file on this Mac (not in the database, so it is not in backups). Erase All Data forgets it.

### Receipt Suggestions (moved into 1.1, planned for next week)

The scan already suggests a total, date and payee, and nothing changes until you press Use. This extends that idea: whatever the scan finds that a transaction doesn't have yet is **offered as a suggestion**, never filled in automatically. The person always decides.

- [ ] Read more from the receipt: tax, tip, a payment method clue (card brand and last four digits, or cash) and a short description, as well as the total, date and store.
- [ ] Suggest more fields: category, payment method and memo, for a blank field ("Add this?") or one that differs ("Change this?"), each with its own Use button, a Use All button, and a way to dismiss one.
- [ ] Learn categories and payment methods as well as payees, per store, on this Mac only (the same small file as the payee memory, which Erase Everything forgets).
- [ ] The same suggestions in every place a receipt can be attached: new transaction, credit card charge, cash transaction and edit (already scan), plus the register's **Add Receipt** link and **Pay a Bill**.
- [ ] Never change anything on its own: suggestions only appear, and a locked or reconciled transaction can't be changed by one.
- [ ] Tests for the receipt parser and the suggestions (sample receipt text), Help and Release Notes updated, screenshots retaken.

## Feature 3: PDF Letterhead ✅ Done

- [x] Printed and exported PDFs get a letterhead generated automatically, with an image, across the top of the first page.
- [x] Decided: both, and it is off by default so nobody has it forced on them. Settings ▸ General ▸ Letterhead can switch it to the Oinkly Budget pig and name, or to your own logo, name and a line of details (for small businesses). The logo is kept on the Mac only, outside backups.
- [x] A custom logo is fitted into the standard letterhead size (600 × 200 pixels, about 2 × 0.65 inch), never enlarged; the name is limited to 40 characters and the details to 90.

## Planning War Room ✅ Done

- [x] The Monthly Outlook page is now the **Planning War Room**, with four tabs: Strategy Plan, Monthly War Plan, Debt War Plan and Savings War Plan.
- [x] The Strategy Plan counts the extra money the Debt and Savings War Plans set aside (always on; closed months keep their figures) and pulls in their statistics, with bar and line charts only: where the month's money goes, what you owe and save over time, net position, when each debt is paid off, how each savings account grows, and what extra money does.
- [x] The Debt and Savings War Plans show what extra money would do and what it takes to be debt-free (or reach your goals) in 1, 2, 3, 5 or 10 years, each with a Use button.
- [x] Monthly War Plan: Add a Line takes a payee with suggestions from the register, and can count towards the Debt or Savings War Plan. Link Transactions is gone.
- [x] No circle graphs anywhere in the app: every one is now a bar or line chart.

## Backups and saving files ✅ Done

- [x] Settings ▸ Data & Backup ▸ **Backup Copy and Save Location**: a switch for a default save location (statements, reports and backups save straight into the folder with no save window) and a switch for the Backup Copy, which starts in the same folder. The start-up prompt and the General reminder are worded to match. Erase Everything forgets the save location.
- [x] The bottom status bar is one dot for this Mac, the Backup Copy and the shared data.

## Other changes ✅ Done

- [x] A separate **Print** button on every account page, beside Print PDF, that opens the Mac's print window for a real printer.
- [x] Investments reports open much faster: their numbers are kept ready and refreshed after changes.
- [x] The Xcode (Debug) build has its own bundle ID and data, so it can no longer touch the copy of the app you use. Release is unchanged.
- [x] Notes removed from the account details and the Edit and Add Account forms. The menu bar pop-up no longer has an Open Oinkly Budget button.
- [x] The **Loan Payoff Goals** tab is removed from Planning, so Planning is one page of savings goals. Payoff goals made earlier stay in the data (and in backups) but are no longer shown anywhere.
- [x] The build is named Laser Focused, You Idiot everywhere (Ridiculous Speed is gone), and the version is 1.1.

## Feature 4: Sparkle automatic updates (flagged for 1.1)

- [ ] The direct-download app (the .dmg from GitHub) checks for new versions by itself and offers to install them, using Sparkle 2, so people don't have to find the release page. The update feed (`appcast.xml`) is built from the GitHub releases folder.
- [ ] Updates are signed with a Sparkle (EdDSA) key kept by the author, on top of the normal Developer ID signing and notarization, so a changed download is refused.
- [ ] Switchable in Settings, with Check for Updates… in the app menu. Only the app version is sent, no personal data.
- [ ] Needs: the Sparkle package added to the project, the network permission and Sparkle's helper permissions in the sandbox, a place to host the feed (a file in the repo or on the website), and a new step in the release checklist that signs the .dmg and adds it to the feed.
- [ ] Only the direct-download build gets Sparkle. A version sent through the App Store must not contain a self-updater, so it needs its own build setting that leaves Sparkle out.
- [ ] Note: 1.0.1 has no Sparkle, so people on 1.0.1 still download 1.1 by hand once. The first real test of an automatic update is the release after 1.1.

## Feature 5: Live prices for holdings (flagged for 1.1)

- [ ] A **Refresh Prices** button (and an optional once-a-day refresh while the app is open) that looks up the current price of each holding by its **ticker symbol only**. The amount held (shares and cost) stays on the Mac and is never sent, so prices update without the holdings having to be re-entered.
- [ ] Source: the author's idea is Yahoo Finance (yfinance). yfinance is a Python library over Yahoo's unofficial pages, which have no official API, can change without warning and are against Yahoo's terms, and a Python library can't go inside a Mac app, so the app would read Yahoo's pages itself and could break at any time. Safer sources with real free tiers are Stooq (no key), Finnhub, Alpha Vantage and Twelve Data (a free key each), and CoinGecko for crypto. Decide at the start; keep the source swappable so a break means changing one file.
- [ ] Opt-in and off by default, with the privacy wording in the README, Help, website and store text changed to say exactly what is sent (ticker symbols only, nothing about amounts or accounts).
- [ ] Needs the network permission (shared with Sparkle).

## ~~Maybe: Paycheck Stub Tracking~~ Cut

- Cut from 1.1.
- The idea was: scan stubs or enter them by hand to keep a running record of pay and withholding, tracking only, with no tax estimates or refund calculations, so it isn't a regulated tax service.

## Still to do before release

**Check on screen or paper** (built, but not yet seen working):

- [ ] The start-up prompt's Choose Folder… (turns on the save location and the Backup Copy together).
- [ ] Saving a PDF, a CSV and a backup straight into the save location.
- [ ] The single status dot with Share with Other Users turned on.
- [ ] The menu bar pop-up without the Open button.
- [ ] A printed PDF with a letterhead and a custom logo.
- [ ] A real Print to paper from an account page.

**Sparkle and live prices** (Features 4 and 5)

- [ ] Built and tried: Sparkle (including a test update from a pretend newer version) and Refresh Prices.
- [ ] The network permission added, and the README, Help, website and store text changed to say what the app now sends.
- [ ] The release checklist gains the Sparkle signing and feed step.

**Receipt Suggestions**

- [ ] Built next week, as described under Feature 2, then added to the checks below.

**Screenshots and words, everywhere**

- [ ] Retake every screenshot, since the Planning War Room, account pages, Settings (Backup Copy and Save Location), reports and more have changed. That is the 71 `Help-…` pictures in the app's Help window, the website's pictures, and any picture in the README. The demo-data mode (`-screenshotMode`) makes them.
- [ ] Update the words to match everywhere: the app's Help window, the in-app Release Notes (1.1 and 1.0.1), the README, and the website (the app page, support page and `updates.html`).
- [ ] Read each place once more at the end for the old names (Monthly Outlook page, Link Transactions, the Quick menu, the Open Oinkly Budget button in the menu bar, the Ridiculous Speed build name) and for "Print PDF" where Print is meant.

**Upgrade test**

- [ ] Install the real 1.0.1 build, add data, then drop the archived 1.1 over it and confirm the data is still there.
- [ ] Decide the build number (1 for 1.1; 1.0.1 was 2).

**Package** (see the release checklist)

- [ ] Archive with the Release configuration; notarize, staple and check with `spctl`.
- [ ] Build the .dmg with the pig background and take its SHA-256.

**Publish**

- [ ] GitHub release v1.1, with the banner image at the top of the notes and the .dmg attached.
- [ ] Point the README's download links and "Latest update" section at v1.1.
- [ ] Website: `updates.html`, the Download buttons, and the page text for the Planning War Room and Strategy Plan.
- [ ] Push the commits; upload the new social preview in the repo's Settings.

## General

- Tweaks and bug fixes throughout the app.

## Future Releases

- **Ludicrous Speed:** planned as the 2.0 release name, but might move up to 1.2 depending on features.
- Ideas for later: optional account sync through SimpleFIN Bridge (paid by the user, read-only), and a watched folder for brokerage CSV imports.
