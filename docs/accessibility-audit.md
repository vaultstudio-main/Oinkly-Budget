# Shortcuts and accessibility audit (step 3)

Drafted 2026-10-18. What was found, what was changed, and what is left.

## Keyboard shortcuts

Before: ⌘N New Transaction, ⌥⌘N New Credit Card Charge, ⇧⌘A ATM Withdrawal, ⇧⌘T Transfer, ⇧⌘B Pay a Bill, ⌥⌘U Update Investment Price, ⇧⌘/ Help, ⌘, Settings, ⌘W close, ⌘Q quit. Delete removes the selected transactions. Sheets use Return for the default button and Escape for Cancel.

Added (built):

| Keys | Command | Where |
|---|---|---|
| ⌘1 to ⌘8 | Summary, Transactions, Reports, Liabilities, Investments, Bills & Recurring, Planning, Budgets | new Go menu |
| ⌘E | Edit Transaction | new Transaction menu |
| ⌘I | View Details | Transaction menu |
| ⇧⌘R | Make Recurring | Transaction menu |

The Transaction commands act on the one selected row of the register that is showing, and are greyed out elsewhere. Import, export and print have no menu items; each page has its own buttons for them (removed from the File menu on request). Everything the right-click menu does on a transaction is now also in a menu, so keyboard-only and VoiceOver users can reach it.

## VoiceOver labels (built)

Before this step the whole app had four accessibility labels. Added labels to the controls that had only an icon: previous and next month and period arrows, clear search, delete buttons on goal entries, tag remove, delete and colour buttons, the split part remove button and its amount field, and the recurring rule actions menu. Account pictures are marked decorative. Tag chips read as "Tag name". Priority bill rows and recurring rule rows read as one item each. Page titles, card titles and report titles are headings, so VoiceOver can jump between them.

## Still to do

| Item | Notes |
|---|---|
| **Edit menu is hidden** | **Decided by the owner, 2026-10-18.** The menu bar stays short: Edit, View and Window are hidden. Copy, paste, cut, select all, undo and redo still work from the keyboard (⌘C, ⌘V, ⌘X, ⌘A, ⌘Z, ⇧⌘Z) in every text field. The cost is that VoiceOver and menu-only users have no Edit menu items. |
| Chart descriptions | **Done at card level.** Every report and trend card now reads its title, what it shows and its headline figure as one item, and VoiceOver can move card by card. The charts inside keep Swift Charts' automatic audio graphs. A hand-written description for each chart could still improve it, if VoiceOver testing shows the need. |
| Table rows | Not checked: needs a person with VoiceOver on. Register rows read their cells in order. |
| Larger text | **Correction:** macOS has no system-wide text size setting that scales a Mac app's fonts, so the 21 fixed font sizes and about 99 fixed widths are not a problem in the way they would be on iPhone. What matters on the Mac is a readable minimum size (the smallest text, `caption2`, is used in 60 places at the system's smallest standard size), contrast, and windows that resize without cutting things off (the main window has a 1000 by 600 minimum). |
| Colour-only meaning | Statuses have words and icons, amounts have signs, and tags have names. Budget bars show a percentage in text. Re-check the Goal section and chart legends. |
| Focus order and focus ring | Tab through every sheet (New, Edit, Split, Recurring, Import, Export). |
| Reduce motion, increase contrast, dark mode | Check the transitions and the dim grey text on dark backgrounds. |
| Help | Document the shortcuts in Help ▸ Keyboard Shortcuts and add an Accessibility topic. |

## How to check (owner, with VoiceOver)

1. Turn on VoiceOver (⌘F5) and move through the side panel, a register, the New Transaction window and the Recurring tab.
2. Every button should say what it does, not "button" or an icon name.
3. Try the Go menu and Transaction menu without the mouse.
4. Turn on larger text and Increase Contrast in System Settings ▸ Accessibility and look for cut-off text.
