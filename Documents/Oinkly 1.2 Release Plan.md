# Oinkly 1.2 Release Plan

**Build name:** to be decided (Ludicrous Speed is kept for 2.0 unless the features say otherwise)

## Overview

Version 1.1 shipped on October 28, 2026. Version 1.2 is about getting real data in: prices for your holdings, receipts proven on real receipts, brokerage files that import themselves, and a look at optional bank sync. In-app humor stays Mel Brooks inspired, mainly Spaceballs.

Four features are planned. They are ordered from the most settled to the least: each of the last two starts with a decision, and the last one may well move to 2.0.

## Carry-over from 1.1

Small things the 1.1 release left open:

- [ ] README: the three edits in `release-build/1.1/readme-latest-update.md` (the version line, "Latest download", the Download link). It still says the newest download is 1.0.1.
- [ ] The update list (`oinklybudget-appcast.xml`) has no entry for 1.1 yet. Add it with `Tools/update-appcast.py` (see `release-build/1.1/RELEASE-STEPS.md`, step 4) so 1.1 is on record, and publish the website.
- [ ] Back up the Sparkle private key (`~/sparkle-tools/generate_keys -x <file>`, kept in a password manager). If it is lost, installed copies can't be updated.
- [ ] Look at the 1.1 disk image window on a clean Mac or account, in case the icon positions need a nudge (the numbers are at the top of `Tools/build-release.sh`).
- [ ] Settings ▸ Data & Backup ▸ Save Backup… straight into the save location, seen working on screen. (The PDF and CSV saves were.)

## Feature 1: Live prices for holdings

Cut from 1.1. A **Refresh Prices** button (and an optional once-a-day refresh while the app is open) that looks up the current price of each holding by its **ticker symbol only**. The amount held (shares and cost) stays on the Mac and is never sent, so prices update without the holdings having to be re-entered.

- [ ] **Decide the source first.** Yahoo Finance (yfinance) is a Python library over Yahoo's unofficial pages, which have no official API, can change without warning and are against Yahoo's terms, and a Python library can't go inside a Mac app anyway. Safer sources: **Finnhub** (official, free key; each user would paste their own free key in Settings, because a key shipped in open-source code can be pulled out and shares one limit), **Stooq** (no key, end-of-day prices, fewer holdings), Alpha Vantage or Twelve Data (free key, low daily limits), and CoinGecko for crypto.
- [ ] Keep the source swappable, so a break means changing one file.
- [ ] Opt-in and **off by default**. The privacy wording changes everywhere to say exactly what is sent (ticker symbols only, nothing about amounts or accounts): README, Help, website privacy page, the Settings text.
- [ ] The network permission is already in the app (added for Sparkle).
- [ ] Tests: price parsing from sample answers, a symbol that isn't found, no network, and a source that changes its format.

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

## Feature 4: Bank sync through SimpleFIN Bridge (look first; may move to 2.0)

An optional, read-only way to bring in transactions: SimpleFIN Bridge is paid for by the user, to SimpleFIN and not to this project, and gives the app a token that can read balances and transactions only. It changes what the app says about itself ("no bank linking"), so it needs a decision before any code.

- [ ] **Decide whether it belongs in the app at all.** The website says "Old school on purpose": nothing connects to your bank. If it goes in, it must be opt-in, off by default, and say so everywhere.
- [ ] If yes: the token kept in the Keychain; what is sent and received written down plainly; transactions arrive as **suggestions to review** (like receipts), never added on their own; a clear way to disconnect and forget the token.
- [ ] If it goes in: the privacy page, README, Help and the in-app text change together, and a test with a made-up server answer.
- [ ] If not for 1.2: write the decision and the reason down in `Documents/`, and move it to the 2.0 ideas.

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
2. **Live prices: which source,** and whether people paste in their own key.
3. **Brokerage files: which brokerages first.**
4. **Bank sync: in the app or not.**

## Future releases

- **Ludicrous Speed:** planned as the 2.0 release name.
- A paycheck stub tracker (cut from 1.1: tracking only, with no tax estimates).
- Anything cut from 1.2.
