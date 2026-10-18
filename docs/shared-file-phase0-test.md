# Shared data file: Phase 0 permissions test

Drafted 2026-10-18. This answers the biggest unknown in `shared-data-file-design.md`: when one Mac login creates a shared folder and a data file, can a different login on the same Mac replace that file, rename it, delete it and add to the receipts folder? It uses the real app's sandbox but never touches your data.

## Round 2 is no longer needed (2026-10-18)

The owner chose an automatic handoff (design decision D16): a second login makes the first one save and close, with no prompts. That works without knowing whether one login can see another login's process, so round 2 below is optional. It would only let the app take over a crashed login's lock instantly instead of after a 20 second wait. Skip it unless you want the extra detail.

## What was set up (round 2, 2026-10-18)

Round 1 passed (see the results below). Round 2 uses the fixed folder the owner chose and the process check that round 1 couldn't reach.

- A new debug build is at `/Users/Shared/OinklyBudget-TestApp-3/OinklyBudget.app`. It has the narrow sandbox exception for `/Users/Shared/OinklyBudget`, so **no panel is needed**.
- Run this copy in **both** logins. Quit any older copy first.

**Round 1 results (panel and `/Users/Shared`):** both logins could replace each other's data file (rename over it and `replaceItemAt`), append to it, take over the lock, replace and delete each other's receipt files, and append to one log. The subfolder stayed open (777, not sticky). The one failure was a login trying to change permissions on a folder it didn't create, which is not needed.

## Steps

**A. The other login is still running**
1. Login 1 (`dstibich`): open the `-3` copy. OinklyBudget ▸ Testing ▸ **Run in /Users/Shared/OinklyBudget**. Leave the app open. Switch users.
2. Login 2 (`lstibich`): open the same copy. OinklyBudget ▸ Testing ▸ **Run in /Users/Shared/OinklyBudget**. Look at the lines under **2b**. Leave the app open. Switch back.

**B. The other login's app has closed**
3. Login 1: **Run in /Users/Shared/OinklyBudget** again, then quit the app with ⌘Q.
4. Login 2: **Run in /Users/Shared/OinklyBudget** again, and look at **2b**.

**Then** tell me it's done. I read the saved reports from `/Users/Shared/OinklyBudget/OinklyBudget-PermissionTest/`. Press **Clean Up** in each login afterwards.

## What the lines mean

| Step | What it proves |
|---|---|
| 1 The shared subfolder | The app can make a folder in `/Users/Shared` that both logins can write to, and that it is not "sticky" (a sticky folder stops one login deleting another's files). |
| 2 The finished data file | The key question: can login 2 replace the file login 1 wrote, the way a save does? |
| 3 The lock file | The lock can be created so only one login wins, and a stale lock can be taken over. |
| 4 The receipts folder | Both logins can add to, replace and delete files in a shared folder. |
| 5 Is another login's app running? | Whether the app can tell a crashed login (so a lock can be taken over at once) or has to wait for the 3 minute timeout. |
| 6 A shared log file | Both logins can append to one file. |

## What I'll do with the result

- **All OK:** the design stands. Phase 1 starts.
- **Replace fails:** I try other folder settings or a different way of replacing the file (copy over in place), and run again.
- **Cannot be made to work:** fall back to the plan's decision D14: ship 1.1 without the shared data file.

A first run on login 1 with no folder chosen through the Open panel is refused by the sandbox ("Operation not permitted"). That is expected and confirms the app must always ask for the folder through the panel, as the design says.
