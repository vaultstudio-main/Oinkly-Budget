# Oinkly 1.1 Release Plan

**Build name:** Laser Focused, You Idiot

## Overview

Version 1.1 is mostly about the debt war plan, plus receipt verification, PDF letterhead, automatic updates (Sparkle), and general polish. In-app humor stays Mel Brooks inspired, mainly Spaceballs.

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

- [x] Read more from the receipt: tax, tip, a payment method clue (card brand and last four digits, or cash) and a short description, as well as the total, date and store.
- [x] Suggest more fields: category, payment method and memo, for a blank field ("Add this?") or one that differs ("Change this?"), each with its own Use button, a Use All button, and a way to dismiss one.
- [x] Learn categories and payment methods as well as payees, per store, on this Mac only. A store is learned as a payee, and the payee already remembers its category, payment method and memo, so no new file was needed.
- [x] The same suggestions in every place a receipt can be attached: new transaction, credit card charge, cash transaction and edit (already scan), plus the register's **Add Receipt** link and **Pay a Bill**.
- [x] Never change anything on its own: suggestions only appear. A locked transaction has no receipt, and the register's receipt link leaves a reconciled one alone.
- [x] Tests for the receipt parser and the suggestions (sample receipt text) and Help and Release Notes updated.
- [ ] Tried on real receipts (groceries, a restaurant with a tip, gas, an online PDF). **Moved to after the 1.1 build**: the author will test it later, so 1.1 ships with the sample-text tests only.

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
- [x] Planning has an **Archive** tab for reached savings goals.
- [x] **Paid-off loans:** a loan that reaches zero is archived (not deleted) to a new **Archived** tab in Manage Accounts (a list to look at only: no View, no Restore), out of the side panel. Their transactions are kept so net worth, debt and interest history stay right, and **each year end the app asks whether to keep or delete them** (Review Archive… asks any time). Student and other loans archive themselves. An auto loan or a mortgage asks first, and offers to add the car or house as a Vehicle or Real Estate asset (worth starting at the original loan amount, with the name and picture copied). When a **lease** ends, a sheet asks what happened to the car: bought it and financed it (the lease becomes a regular auto loan owing the buyout), bought it outright (a Vehicle asset), or returned it (archived). A line of credit or HELOC is left alone.
- [x] The **Loan Payoff Goals** tab is removed from Planning, so Planning is only savings goals. Payoff goals made earlier stay in the data (and in backups) but are no longer shown anywhere.
- [x] The build is named Laser Focused, You Idiot everywhere (Ridiculous Speed is gone), and the version is 1.1.

## Feature 4: Sparkle automatic updates (flagged for 1.1)

**Decisions (Oct 28):** GitHub download only (no App Store build, so Sparkle is in every release build); the update list lives on the website at `https://vaultstudio.dev/oinklybudget-appcast.xml` (moved from the repo on Oct 28, so it stays put if the repo moves) and is published with the website; Sparkle asks once ("Check for updates automatically?") on the second launch and only checks if you say yes; the update window shows the release notes (a Markdown file given to `Tools/update-appcast.py --notes`) with a link to the GitHub release page.

**Pieces to build:**

- [x] The Sparkle 2 package added to the Xcode project.
- [x] The updater starts at launch in every build, so it also shows in the Xcode build (a Debug build can use a local test feed). **Check for Updates…** in the app menu, and a switch in Settings for automatic checks.
- [x] Project settings: the feed address (`SUFeedURL`), the public signing key (`SUPublicEDKey`), the installer helper switch for the sandbox (`SUEnableInstallerLauncherService`), the network permission, and the two mach-lookup permissions Sparkle's helpers need (`<bundle ID>-spks` and `-spki`).
- [x] The signing key (back up the private key: still to do by you): made with Sparkle's `generate_keys`; the private half stays in your login Keychain and **must be backed up** (if it is lost, existing installs can't be updated). The public half goes in the app.
- [x] `oinklybudget-appcast.xml` in the website folder (`Tools/update-appcast.py` adds each release), one entry per release: version, build, download link (the .dmg on the GitHub release), signature, size and the release page for what's new.
- [x] The release checklist gains the step: sign the notarized .dmg with `sign_update`, add its entry to `oinklybudget-appcast.xml`, publish the website.
- [x] Tested with a local feed and a pretend newer version. The first real automatic update is the release after 1.1, because 1.0.1 has no Sparkle.
- [ ] Wording: README, Help, the website and the store text say exactly what an update check sends (the app and system version only, no personal data), and that it asks first.

## ~~Feature 5: Live prices for holdings~~ Cut from 1.1 (Oct 28)

Scratched for now: not in 1.1, to be looked at again later (the notes below stay for then).

- [ ] A **Refresh Prices** button (and an optional once-a-day refresh while the app is open) that looks up the current price of each holding by its **ticker symbol only**. The amount held (shares and cost) stays on the Mac and is never sent, so prices update without the holdings having to be re-entered.
- [ ] Source: the author's idea is Yahoo Finance (yfinance). yfinance is a Python library over Yahoo's unofficial pages, which have no official API, can change without warning and are against Yahoo's terms, and a Python library can't go inside a Mac app, so the app would read Yahoo's pages itself and could break at any time. Safer sources with real free tiers are Stooq (no key), Finnhub, Alpha Vantage and Twelve Data (a free key each), and CoinGecko for crypto. Decide at the start; keep the source swappable so a break means changing one file.
- [ ] Opt-in and off by default, with the privacy wording in the README, Help, website and store text changed to say exactly what is sent (ticker symbols only, nothing about amounts or accounts).
- [ ] Needs the network permission (shared with Sparkle).

## ~~Maybe: Paycheck Stub Tracking~~ Cut

- Cut from 1.1.
- The idea was: scan stubs or enter them by hand to keep a running record of pay and withholding, tracking only, with no tax estimates or refund calculations, so it isn't a regulated tax service.

## Still to do before release

**Check on screen or paper** (built, but not yet seen working):

- [x] The start-up prompt's Choose Folder… (turns on the save location and the Backup Copy together). Seen working Oct 28.
- [x] Saving a PDF, a CSV and a backup straight into the save location. PDF and CSV seen working Oct 28; the backup (Settings ▸ Data & Backup ▸ Save Backup…) still to click.
- [x] The single status dot with Share with Other Users turned on. (checked by the author)
- [x] The menu bar pop-up without the Open button. (checked by the author)
- [x] A printed PDF with a letterhead and a custom logo. (checked by the author)
- [x] A real Print to paper from an account page. (checked by the author)

**Sparkle** (Feature 4)

- [x] Built and tried: Sparkle (a test update from a pretend newer version installed and relaunched).
- [x] The network permission added.
- [x] The README, Help (new Updates topic, Welcome, Your Data & Privacy, Settings), the in-app Release Notes, and the website's privacy, product and support pages say what the app now sends (an update check: app and macOS version only, and it asks first). Written Oct 28; the website text goes live with 1.1. Store text: not needed (GitHub download only).
- [x] The release checklist gains the Sparkle signing and feed step.

**Receipt Suggestions**

- [x] Built, as described under Feature 2. The real-receipt trial moves to after the 1.1 build; the screenshots are retaken with the others below.

**Screenshots and words, everywhere**

- [x] Retake every screenshot. Done Oct 28: the screenshot tour (`-screenshotMode`) makes them and `Tools/install-help-pictures.py` installs them: the 71 `Help-…` pictures (plus six new ones for the War Plan tabs, the Archive tabs and Updates) and the website's 33 pictures (`--website`; three new War Plan pictures on the product page). The README only has the social preview. The Receipt Suggestions picture waits for the real-receipt trial after the build.
- [x] Update the words to match everywhere: the app's Help window, the in-app Release Notes (now only 1.1), the README, and the website's app page, support page and privacy page. The website's `updates.html` has a Version 1.1 entry with the banner ("Coming soon", no download button). Still at release time: set its date, add the Download button, and point the Projects card and the Download links at v1.1 (they must say v1.1 only once it is published).
- [x] Read each place for the old names (Monthly Outlook page, Link Transactions, the Quick menu, the Open Oinkly Budget button, Ridiculous Speed) and for "Print PDF" where Print is meant. Done Oct 28; the Release Notes keep the old names only to say what was renamed.

**Upgrade test**

- [x] Install the real 1.0.1 build, add data, then drop the archived 1.1 over it and confirm the data is still there. Done Oct 28: the author dropped 1.1 over 1.0.1 and nothing broke (the data models did not change between 1.0.1 and 1.1).
- [x] Build number decided: 1.1 is build 10 (Sparkle compares it, and 1.0.1 was build 2). Every release after goes up.

**Package** (see the release checklist)

- [x] Archive with the Release configuration; notarize, staple and check with `spctl`. Done Oct 28: version 1.1 build 10, Developer ID, notarized and stapled. (Made in the project's `release-build/1.1/` folder, which Git ignores; `Tools/build-release.sh 1.1` checks the app and builds the .dmg.)
- [x] Build the .dmg with the pig background and take its SHA-256. Done Oct 28 with `Tools/build-release.sh 1.1` (39 MB): SHA-256 `962ff0d80cd973b3f3800afbfcb35cfd2aa0c459fac8f74ea34434e0c09cd5a0`. The app inside was checked from the mounted image: signed, notarized and stapled. Never rebuild it after it is uploaded.

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
