# OinklyBudget 1.2: plan

Drafted 2026-10-18. Nothing here is started. Work on 1.2 begins right after 1.1 ships, and the first item below is where it starts.

## Goal

Tie the planning side of the app to real accounts, and finish what 1.1 left for later. The direction stays the same: a full desktop program, no bank linking, no accounts, no network.

## First thing: goals tied to accounts

Goals used to be able to follow an account, and 1.0 deliberately stopped that (a step that runs at every launch, `GoalMigration.detachAccounts`, turns old linked goals into plain ones). The database still keeps the `account` field on each goal, so this needs **no database change on its own**.

| Goal | What it would do |
|---|---|
| **Savings goal tied to a checking or savings account** | Progress follows the account's balance, so deposits count by themselves. A "count only what's added from now on" choice keeps an account that already holds money from starting the goal half full. |
| **Debt payoff tied to a loan** | Progress is what the loan owed when the goal was made minus what it owes now. Payments recorded with Pay a Bill move the goal on their own. |

How it should behave:

- Linking is a choice when the goal is made. Goals that aren't linked keep working as they do now.
- A linked goal can't also take manual progress, because the balance is the truth. Say so on the goal.
- The unlinking step that runs at launch has to stop, and goals that were already unlinked stay as they are.
- Show the linked account on the goal's card, and show the goal on the account's page.

Open questions (decide before building):

1. **Why were goals unlinked in 1.0?** If it was because linked goals confused people, keep linking clearly optional and labelled.
2. **Two goals on one account** (a vacation and an emergency fund in one savings account): each would show the whole balance. Either allow one linked goal per account, or let a linked goal claim a set amount of the balance.
3. **Closed or deleted accounts:** what a linked goal does when its account goes away. Suggestion: keep the goal, freeze its last amount, and say the account is gone.

Effort: about 3 to 4 days, plus testing on a copy of real data.

## One database change, done once

Several things want a stored field. Doing them together means one migration instead of several.

| Item | Why it needs a field |
|---|---|
| **Primary checking on the account itself** | 1.1 keeps it as a setting on the Mac. As a field it travels with backups and the shared data file. |
| **Split transactions** | One payment across several categories. |
| **Recurring transactions** | Paycheque, rent and so on, with a reminder or an automatic entry. |
| **Tags** on transactions | Usable in reports. |

The catch: the database is declared as `PiggybankSchemaV1`, and a new `PiggybankSchemaV2` needs a frozen copy of all ten models as they are in 1.1, plus a tested migration between them. That is the biggest part of the work. Plan it as its own step first:

- Back up before updating; make the migration test part of release testing.
- Test the migration on copies of real data, including a large one.
- Keep every change a field with a default, so the migration stays an automatic, lightweight one.

Splits, recurring and tags are in the 1.1 "Should have" list. Anything not built in 1.1 moves here and uses this migration. Effort: about 1 week for the migration itself, then 3 days to 2 weeks for each feature.

## Finish what 1.1 left

- **PDF for more pages.** The builders for net worth, bills, reports and the budget are written, but no page has a button for them. Decide where they go, if anywhere.
- **Check printing layout** (optional): print checks on standard check stock.
- **Attachments beyond receipts:** PDF statements kept with an account.
- **Keyboard shortcuts review** and more menu commands.
- **Accessibility pass** (VoiceOver, larger text) for the screens added in 1.1 and 1.2.
- **Settings for default report period, paper size and export style.**
- **Widgets:** more sizes or a configurable widget (choose which bills or reminders) if people ask for it.

## Release housekeeping

- Version 1.2, build number up by one for every upload.
- Help pages and screenshots for each new feature, release notes, website and listing update.
- A schema change means the release notes and Help tell users to make a `.pig` backup before updating.
- New App Review notes if anything changes about data handling.

## Rough effort

| Part | Effort |
|---|---|
| Goals tied to accounts | 3 to 4 days |
| Database migration (V2) | about 1 week |
| Each stored-field feature (splits, recurring, tags) | 3 days to 2 weeks |
| PDF pages, attachments, accessibility, settings | 1 to 2 weeks |
| Help, screenshots, release | 1 week |

About 5 to 8 weeks part-time. If it slips, drop the optional items first and keep goals tied to accounts and the migration.

## Risks

- **The migration.** An existing database that can't open is the worst outcome. Back up first, test on copies, and keep every change a defaulted field.
- **Linked goals can mislead** (two goals on one account, a closed account). The questions above exist to head that off.
- **Scope.** Goals tied to accounts is the headline. Don't let the optional list crowd it out.

## Decisions needed

1. Goals tied to accounts: why they were unlinked, and the answers to the three questions above.
2. Which of splits, recurring and tags are built in 1.1 and which move here.
3. Where the extra PDFs (net worth, bills, reports, budget) belong, if anywhere.
4. Release timing, after 1.1 is approved.
