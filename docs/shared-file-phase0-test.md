# Shared data file: Phase 0 permissions test

Drafted 2026-10-18. This answers the biggest unknown in `shared-data-file-design.md`: when one Mac login creates a shared folder and a data file, can a different login on the same Mac replace that file, rename it, delete it and add to the receipts folder? It uses the real app's sandbox but never touches your data.

## What was set up

- A debug build of the app is copied to `/Users/Shared/OinklyBudget-TestApp/OinklyBudget.app`, readable by every login. Run this copy in **both** logins so both run exactly the same build.
- The Mac has two accounts (`dstibich` and `lstibich`) and fast user switching is on.
- The test lives in OinklyBudget ▸ Testing ▸ **Sharing permission test**. It writes only into a test folder it makes, called `OinklyBudget-PermissionTest`, inside the folder you choose.

## Steps

Run in this order. Do not log either account out; use fast user switching (the user menu in the menu bar, or Control Center).

**Login 1 (`dstibich`, the first run)**
1. Open `/Users/Shared/OinklyBudget-TestApp/OinklyBudget.app`. (Use this copy, not the one from Xcode.)
2. Choose OinklyBudget ▸ Testing. In **Sharing permission test**, press **Choose Folder…**, pick `/Users/Shared`, then **Use This Folder**.
3. Press **Run Test**. Every line should say OK or INFO. Press **Copy Results** if you want to keep them.
4. Leave the app open. Switch users.

**Login 2 (`lstibich`)**
5. Open the same app (`/Users/Shared/OinklyBudget-TestApp/OinklyBudget.app`). If macOS refuses to open it, right-click it and choose Open. It starts with an empty app; that is fine.
6. OinklyBudget ▸ Testing ▸ **Choose Folder…**, pick `/Users/Shared`, **Use This Folder**, then **Run Test**.
7. This run is the important one. Anything that says **FAIL** matters, especially "COULD NOT REPLACE it", "Could not take over the lock" or "Could not delete".
8. Switch back to login 1.

**Login 1 again**
9. Press **Run Test** once more. It now handles files login 2 made.

**Then**
10. In either login, tell me it's done. I read the saved reports directly from `/Users/Shared/OinklyBudget-PermissionTest/` (`report-dstibich.txt`, `report-lstibich.txt`).
11. Press **Clean Up** in each login when finished (the folder may stay if the other login's files remain; I can remove it).

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
