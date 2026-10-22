# Data integrity plan for 1.0

Drafted 2026-10-18. The rule behind everything here: **no client loses information**, not in the upgrade from the original build, not in a backup restore. Nothing is submitted until every check below has passed on the release candidate.

## Promises

1. An update never opens an empty or blank database over someone's data.
2. Before the first open of the new database shape, a copy of everything exists and is kept until the person deletes it.
3. If the database can't be opened, the app says so and stops. It never creates a fresh database in its place.
4. Migration never replaces a good file with a file that has not been checked.
5. A backup made by any earlier build restores into the current build.

## What is already in place (built and tested by hand)

| Protection | Where | Tested |
|---|---|---|
| Frozen V1 shape and a lightweight V1 to V2 migration | `Models/SchemaV1Models.swift`, `SchemaVersions.swift` | Real database from the original build (1.0 build 1, tag `app-review-original-1.0`) opened by the current build, test data set |
| One-time step after migration (routing numbers, opening-deposit flag, tax flags, primary checking) | `Logic/SchemaUpgrade.swift` | Same test |
| Safety copy before first V2 open (data file, side files, receipts folder) | `Logic/StoreSafetyCopy.swift` | Same test |
| Data file pinned to the app's own folder, so the App Group can't move it | `PiggybankApp.swift`, `AppStore.localStoreURL` | Found and fixed by comparing the original build and the new one |
| Open failure shows an error screen, not an empty database | `PiggybankApp.swift`, `StartupState` | By design, not forced yet |

## Gaps to close (each becomes a test below)

- Large data (about 4,000 transactions and more) has not been tested.
- No automated tests for the migration.
- Restore of a backup from the original build into the current build is untested.
- Interrupted upgrade (kill during the first open) is untested.
- Splits, tags and recurring rules are not stored in real data yet.

## Test plan

Run these on every release candidate. Record the date, the build and pass or fail in the table at the bottom.

### A. Upgrade from the original build

| # | Test | Pass when |
|---|---|---|
| A1 | Build the original from the tag `app-review-original-1.0`, fill it with the test data set, open the same data with the release candidate | Every account, transaction, bill, goal, budget, holding, payee and receipt is there; balances match the 1.0 numbers to the cent |
| A2 | Same as A1 with a large data set (4,000 and then 20,000 transactions) | Same result; the first open finishes in reasonable time; no crash |
| A4 | Upgrade with the old data file in an unusual state (wal and shm side files present, receipts folder large) | Same result; the safety copy contains them |
| A5 | Kill the app during the first open | Next launch opens normally or restores from the safety copy; nothing missing |
| A6 | Run the upgrade twice (open, quit, open) | No duplicate Deposits, categories or payees |
| A7 | Open on a Mac with the old data file in a read-only or full-disk situation | A clear error, the original data untouched |
| A8 | Verify the safety copy by opening it with the original build | It opens and has all the data |
| A9 | Compare a totals report before and after (net worth, every account balance, count of transactions, count of receipts) | Identical |

### B. Backup and restore

| # | Test | Pass when |
|---|---|---|
| B1 | Backup made by the original build, restored into the release candidate | All data back, new fields get sensible defaults |
| B2 | Backup made in the release candidate, restored into the same build on an empty database | All data back, including splits, tags and rules |
| B4 | Restore on top of existing data | The person is warned first; a failure leaves the existing data untouched |
| B5 | Restore a backup that was cut short or edited | Refused with a clear message, existing data untouched |


| # | Test | Pass when |
|---|---|---|

### D. New data (splits, tags, recurring)

| # | Test | Pass when |
|---|---|---|
| D1 | Splits add up to the total; editing and deleting keeps them consistent | Reports count each part once |
| D2 | Deleting a category, tag or account that splits and rules use | No orphan rows; a clear message |
| D3 | Backup and restore with splits, tags and rules | Identical afterwards |
| D4 | A recurring rule run twice for the same date | One pending entry, not two |

### F. Every release candidate

| # | Check |
|---|---|
| F1 | Version and build number are higher than anything already uploaded |
| F2 | Schema version matches what is in the shipped build; V2 is not edited after anyone outside this Mac has used it, or a V3 and migration are added |
| F3 | The release notes tell people to make a backup, and where the safety copy is |
| F4 | A fresh install works (no old data) |
| F5 | The release build, not the debug build, is the one tested |

## Rules while building

- A change to a stored model is a schema change. Once V2 has left this Mac (TestFlight or the store), changing it needs V3 and a tested migration.
- Every new stored field has a default, so the migration stays lightweight.
- A step that changes data must be safe to run twice.
- Never delete the old data until the new data has been checked. Check by reading it back, not by trusting the write.
- Never fall back to an empty database on an error.
- Write failures leave the old file in place (write to a temporary file, verify, then replace).

## Record

| Date | Build | Tests run | Result | Notes |
|---|---|---|---|---|
| 2026-10-18 | main at b374987 and 4a0d4c2 | A1, A3, location check | Passed | Test data set only; no large data yet |
