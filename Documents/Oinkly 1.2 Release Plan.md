# Oinkly 1.2 Release Plan

**Build name:** to be decided (Ludicrous Speed is kept for 2.0 unless the features say otherwise)

## Overview

Version 1.1 shipped on October 28, 2026. Version 1.2 is about getting real data in, on the person's own Mac and with nothing to sync: receipts proven on real receipts, and brokerage files that import themselves. In-app humor stays Mel Brooks inspired, mainly Spaceballs.

**Nothing in 1.2 connects to an outside service.** Live prices and bank sync were looked at and dropped (see Dropped, below): the app stays old school, and the person enters or imports their own numbers.

Two features are planned.

## Carry-over from 1.1

Small things the 1.1 release left open:

- [x] README: the three edits from `release-build/1.1/readme-latest-update.md` (the version line, "Latest download", the Download link). Done Oct 29. It needs pushing.
- [ ] The update list (`oinklybudget-appcast.xml`): the 1.1 entry is added and its signature verified against the DMG (Oct 29; the GitHub download was checked as byte-for-byte the same file). **Still to do: publish the website**, because the live list at vaultstudio.dev/oinklybudget-appcast.xml is still the empty one. The rest of the site (Updates page, download links) is already live.
- [ ] Back up the Sparkle private key (`~/sparkle-tools/generate_keys -x <file>`, kept in a password manager). If it is lost, installed copies can't be updated.
- [ ] Look at the 1.1 disk image window on a clean Mac or account, in case the icon positions need a nudge (the numbers are at the top of `Tools/build-release.sh`).
- [ ] Settings ▸ Data & Backup ▸ Save Backup… straight into the save location, seen working on screen. (The PDF and CSV saves were.)

## Feature 1: Receipts, proven on real ones

Receipt Suggestions shipped in 1.1 and was tested on sample text only. This is the real-world pass.

- [ ] Try it on real receipts: groceries, a restaurant with a tip, gas, an online PDF. Write down what it gets wrong.
- [ ] Fix the parser and the suggestions for what turns up, with a test for each fix (sample text from the real receipt, with names and numbers changed).
- [ ] Take the Receipt Suggestions screenshots for Help and the website, and add them to the screenshot tour.
- [ ] Check **Pay a Bill** and the register's **Add Receipt** link on screen with a real receipt.

## Feature 2: Brokerage CSV import from a watched folder

Drop a brokerage CSV into a folder and Oinkly Budget picks it up, with a preview first, never changing anything on its own.

- [ ] **Decide the scope:** which brokerages' files to support first (for example Fidelity, Schwab and Vanguard), and whether it watches a folder or simply remembers one you choose in the import window.
- [ ] The folder is chosen by the person and kept as a bookmark in the app's sandbox (read access to that one folder only).
- [ ] A preview with counts, the same as the bank CSV import, and **Undo**.
- [ ] Recognize holdings, transactions (buys, sells, dividends) and cash movements, and match them to the investment accounts already there; never create duplicates when the same file is dropped twice.
- [ ] Saved formats, like the bank import has.
- [ ] Tests with sample files of each brokerage's layout (made-up data).

## Other changes in 1.2 (so far)

- [x] **Settings: Tags is merged into Clean Up** (Oct 29). Clean Up has a choice at the top, Payees, Categories or Tags, so Settings has one tab fewer. Someone whose Settings window was last left on the old Tags tab opens on Clean Up ▸ Tags. Help, the Settings tour and the Help picture caption are updated. **At release:** change the website's support answer ("Settings ▸ Tags" becomes "Settings ▸ Clean Up ▸ Tags"), retake the `Help-tags-settings` and `Help-cleanup` pictures, and add the change to the 1.2 Release Notes.

## Testing the first real update

1.1 is the first version with Sparkle, so **1.2 is the first real automatic update**.

- [ ] Add the 1.2 entry to the update list and publish it, with the notes file.
- [ ] On a Mac running 1.1 with automatic checks on, see the update offered, with the release notes in the window, installed, and the app reopened as 1.2 with its data intact.
- [ ] Also try **Check for Updates…** by hand, and "Remind Me Later" and "Skip This Version".
- [ ] The build number goes up from 10 (use 11 or higher).

## Before the release (the same steps as 1.1)

Everything for a release lives in `release-build/<version>/`: copy `release-build/1.1/` to `release-build/1.2/` and change the wording, the version, the build number and the SHA-256.

- [ ] Version 1.2 and the new build number in the Xcode project, **for the app and for the widget extension** (the widget's `CURRENT_PROJECT_VERSION` and `MARKETING_VERSION` must match the app's, or Xcode warns that the extension's CFBundleVersion doesn't match its parent app).
- [ ] Release Notes in the app: only 1.2's new things (the window lists one release).
- [ ] Retake the screenshots with the tour (`-screenshotMode`), and install them with `Tools/install-help-pictures.py` (Help) and `--website` (website). Add shots for what is new first.
- [ ] Words: Help, the in-app Release Notes, the README, the website's app, support and privacy pages, and `updates.html`.
- [ ] The release banner: `swift Tools/make-release-banner.swift Documents/social-preview.png Documents/social-preview-1.2.png 1.2 "<build name>"`, copied into the app's `Release-banner` image set.
- [ ] Upgrade test from 1.1: drop 1.2 over it with real data and confirm it opens as it was.
- [ ] Archive, notarize, build the DMG (`Tools/build-release.sh 1.2`).
- [ ] GitHub release `v1.2`, the update list, the website, the README, and push.

## Open decisions

1. **The 1.2 build name.** To be decided.
2. **Brokerage files: which brokerages first.**

## Dropped

- **Live prices for holdings** (dropped October 29, 2026). A Refresh Prices button was designed as bring your own key (Finnhub first), but it depended on a company's permission (the terms say personal use only and say nothing about third-party apps, so the plan was to email them), on a network service staying the same, and on keys, limits and coverage the app doesn't control; free sources also look weak on mutual funds. The author's decision: nothing that has to sync or ask a company. Prices stay as they are today, typed in through Update Investment Price, and the brokerage CSV import (Feature 2) can bring in prices from the person's own file with nothing sent anywhere. If it is ever revisited, the research is in this file's history (commit `c79ecf8`).
- **Bank sync through SimpleFIN Bridge** (dropped October 29, 2026). It would have let the app read balances and transactions from the bank through a service the user pays for ($15 a year). Dropped because none of the author's banks are supported, so it couldn't be tested on real data, and because it cuts against "old school on purpose": the app stays free of any bank connection. If it is ever revisited, the findings are: the user pays SimpleFIN, not the project; a one-time setup token is traded for an access address that has to be kept like a password (the Keychain); balances and raw-text transactions come back, with no categories or merchant names; at most 90 days per request and about 24 requests a day; and the hard part is matching what the bank reports against what the person has already entered.

## Future releases

- **Ludicrous Speed:** planned as the 2.0 release name.
- A paycheck stub tracker (cut from 1.1: tracking only, with no tax estimates).
- Anything cut from 1.2.
