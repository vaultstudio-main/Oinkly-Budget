# Oinkly 1.2 Release Plan

**Build name:** to be decided (Ludicrous Speed is kept for 2.0 unless the features say otherwise)

## Overview

Version 1.1 shipped on October 28, 2026. Version 1.2 is about getting real data in: prices for your holdings, receipts proven on real receipts, and brokerage files that import themselves. In-app humor stays Mel Brooks inspired, mainly Spaceballs.

Three features are planned. Live prices comes first and starts with a decision and a test before any code. Bank sync through SimpleFIN was looked at and **dropped** (see Dropped, below).

## Carry-over from 1.1

Small things the 1.1 release left open:

- [x] README: the three edits from `release-build/1.1/readme-latest-update.md` (the version line, "Latest download", the Download link). Done Oct 29. It needs pushing.
- [ ] The update list (`oinklybudget-appcast.xml`): the 1.1 entry is added and its signature verified against the DMG (Oct 29; the GitHub download was checked as byte-for-byte the same file). **Still to do: publish the website**, because the live list at vaultstudio.dev/oinklybudget-appcast.xml is still the empty one. The rest of the site (Updates page, download links) is already live.
- [ ] Back up the Sparkle private key (`~/sparkle-tools/generate_keys -x <file>`, kept in a password manager). If it is lost, installed copies can't be updated.
- [ ] Look at the 1.1 disk image window on a clean Mac or account, in case the icon positions need a nudge (the numbers are at the top of `Tools/build-release.sh`).
- [ ] Settings ▸ Data & Backup ▸ Save Backup… straight into the save location, seen working on screen. (The PDF and CSV saves were.)

## Feature 1: Live prices for holdings (bring your own key)

A **Refresh Prices** button that looks up the current price of each holding by its **ticker symbol only**. The amount held (shares and cost) never leaves the Mac. Cut from 1.1; designed in the open on October 29, 2026. Nothing is built yet.

### The design, as decided

- **Bring your own key.** The app ships with no key and no price data. Each person signs up for their own free key (Finnhub first) and pastes it into Settings. Finnhub's plans are for **personal use**, and personal and family finances are exactly that. The app says so next to the key field, and that a business can't use a personal key.
- **The key stays on the person.** It is kept in the Mac's Keychain, outside the database, outside backups and outside the shared data, like the letterhead logo and the receipt memory. Erase All Data forgets it. Someone who restores a backup on another Mac keeps the prices in it but has to paste their own key to refresh.
- **The prices belong to the data.** A price, its date and the history it makes are saved with everything else and carry over into backups and across Macs, so the price fluctuation is part of the person's own records.
- **Off by default, and nothing changes on its own.** An opt-in switch in Settings. Refresh Prices shows what was found, with each holding's old and new price and the as-of time, and nothing is applied until Use (Use All or Use Selected), the same promise as receipts.
- **One file per source.** A small "give me prices for these tickers" interface, with Finnhub as the first implementation, so a provider that turns out wrong is replaced by changing one file.

### What the code already gives us

- A holding already has a free-text ticker (`symbol`), a price and a price date, so **no new data fields and no migration**.
- `HoldingsLedger.updatePrice` also posts a **growth transaction** to the account ("Price update: VTSAX"). Applying 20 prices that way would add 20 transactions per refresh, so Refresh Prices needs a **batch update**: each holding's history is recorded as now, but **one growth transaction per account** per refresh.
- A found price is only offered if its as-of time is newer than the stored price date, so it never overwrites a newer hand-entered price.

### What is known about Finnhub

Confirmed on October 29 from their spec and terms: the key goes in a header (`X-Finnhub-Token`); going over the limit returns HTTP 429, and there is a cap of 30 calls a second; a symbol search exists; the mutual fund endpoints in the spec are profile and holdings only, **with no price**; the plans are for personal use only, and redistributing "data or derived results" or sharing access needs written approval; the data must be deleted when the subscription ends; Finnhub logs queries; the terms say nothing about third-party apps.

Not confirmed (the docs pages would not load): the exact quote fields (current price, previous close, timestamp are recalled), the free limit (about 60 calls a minute is recalled), US stocks and ETFs only, and zeros for an unknown symbol. The spike settles these.

### Build order

- [ ] **M0, before any code:** email Finnhub support to ask whether an open-source desktop app where each person uses their own personal key is allowed (a draft will be written for the author to send). Sign up for a free key and run **six real tickers** (a stock, an ETF, a mutual fund, a crypto coin, a foreign ticker, and one that doesn't exist) from a local test script, with the key kept out of Git. Decide go or no-go, and whether another provider is needed.
- [ ] **M1:** the price source interface, the Finnhub implementation, and tests with canned answers (success, unknown symbol, wrong key, over the limit, no network, a changed format). No screens yet.
- [ ] **M2:** Settings: the opt-in switch, the key field (Keychain), Test Key, a link to sign up, and the text saying exactly what is sent and that it is for personal use.
- [ ] **M3:** Refresh Prices on the Investments page and in the File menu: the review sheet, the skipped list with reasons (no ticker, mutual fund, not found), and the batch apply with one growth transaction per account.
- [ ] **M4:** optional: a symbol search in the Add Holding sheet, using Finnhub's search.
- [ ] **M5:** a fake price source for the screenshot tour, the Help topic, the privacy wording (Settings, Help, the website privacy page, the README, the support page) and the Release Notes.
- [ ] **M6:** on-screen checks with a real key, and the upgrade path from 1.1.

### Risks and what they mean for the wording

- **The terms don't mention third-party apps.** The email in M0 is the answer. Until then, the app doesn't ship a key or any data, and all use is the person's own.
- **Business use isn't allowed on a personal key.** The wording says "personal use" next to the key field.
- **Coverage.** Free Finnhub is probably US stocks and ETFs. Crypto symbols use another format (an exchange prefix such as `BINANCE:BTCUSDT`) and mutual funds look unavailable. In 1.2, only what is covered gets priced, and the sheet says what was skipped and why; the rest stays by hand or comes from the brokerage import (Feature 3).
- **What leaves the Mac:** the tickers you hold and your key, and Finnhub can see your internet address and logs queries. Said plainly in the app, Help, the website and the README.
- **Family use:** the prices are saved data and can be shared by the family; each person who refreshes needs their own key, because sharing a key is restricted.

### Decisions still open

1. Refresh by hand only in 1.2, or also once a day while the app is open? (Recommended: by hand only, since a daily refresh changes data without being asked.)
2. One growth transaction per account per refresh, or one per holding as today? (Recommended: one per account.)
3. The exact wording for business users beside the key field.

## Feature 2: Receipts, proven on real ones

Receipt Suggestions shipped in 1.1 and was tested on sample text only. This is the real-world pass.

- [ ] Try it on real receipts: groceries, a restaurant with a tip, gas, an online PDF. Write down what it gets wrong.
- [ ] Fix the parser and the suggestions for what turns up, with a test for each fix (sample text from the real receipt, with names and numbers changed).
- [ ] Take the Receipt Suggestions screenshots for Help and the website, and add them to the screenshot tour.
- [ ] Check **Pay a Bill** and the register's **Add Receipt** link on screen with a real receipt.

## Feature 3: Brokerage CSV import from a watched folder

Drop a brokerage CSV into a folder and Oinkly Budget picks it up, with a preview first, never changing anything on its own.

- [ ] **Decide the scope:** which brokerages' files to support first (for example Fidelity, Schwab and Vanguard), and whether it watches a folder or simply remembers one you choose in the import window.
- [ ] The folder is chosen by the person and kept as a bookmark in the app's sandbox (read access to that one folder only).
- [ ] A preview with counts, the same as the bank CSV import, and **Undo**.
- [ ] Recognize holdings, transactions (buys, sells, dividends) and cash movements, and match them to the investment accounts already there; never create duplicates when the same file is dropped twice.
- [ ] Saved formats, like the bank import has.
- [ ] Tests with sample files of each brokerage's layout (made-up data).

## Testing the first real update

1.1 is the first version with Sparkle, so **1.2 is the first real automatic update**.

- [ ] Add the 1.2 entry to the update list and publish it, with the notes file.
- [ ] On a Mac running 1.1 with automatic checks on, see the update offered, with the release notes in the window, installed, and the app reopened as 1.2 with its data intact.
- [ ] Also try **Check for Updates…** by hand, and "Remind Me Later" and "Skip This Version".
- [ ] The build number goes up from 10 (use 11 or higher).

## Before the release (the same steps as 1.1)

Everything for a release lives in `release-build/<version>/`: copy `release-build/1.1/` to `release-build/1.2/` and change the wording, the version, the build number and the SHA-256.

- [ ] Version 1.2 and the new build number in the Xcode project.
- [ ] Release Notes in the app: only 1.2's new things (the window lists one release).
- [ ] Retake the screenshots with the tour (`-screenshotMode`), and install them with `Tools/install-help-pictures.py` (Help) and `--website` (website). Add shots for what is new first.
- [ ] Words: Help, the in-app Release Notes, the README, the website's app, support and privacy pages, and `updates.html`.
- [ ] The release banner: `swift Tools/make-release-banner.swift Documents/social-preview.png Documents/social-preview-1.2.png 1.2 "<build name>"`, copied into the app's `Release-banner` image set.
- [ ] Upgrade test from 1.1: drop 1.2 over it with real data and confirm it opens as it was.
- [ ] Archive, notarize, build the DMG (`Tools/build-release.sh 1.2`).
- [ ] GitHub release `v1.2`, the update list, the website, the README, and push.

## Open decisions

1. **The 1.2 build name.** To be decided.
2. **Live prices:** the three decisions at the end of Feature 1, and Finnhub's answer to the email (M0).
3. **Brokerage files: which brokerages first.**

## Dropped

- **Bank sync through SimpleFIN Bridge** (dropped October 29, 2026). It would have let the app read balances and transactions from the bank through a service the user pays for ($15 a year). Dropped because none of the author's banks are supported, so it couldn't be tested on real data, and because it cuts against "old school on purpose": the app stays free of any bank connection. If it is ever revisited, the findings are: the user pays SimpleFIN, not the project; a one-time setup token is traded for an access address that has to be kept like a password (the Keychain); balances and raw-text transactions come back, with no categories or merchant names; at most 90 days per request and about 24 requests a day; and the hard part is matching what the bank reports against what the person has already entered.

## Future releases

- **Ludicrous Speed:** planned as the 2.0 release name.
- A paycheck stub tracker (cut from 1.1: tracking only, with no tax estimates).
- Anything cut from 1.2.
