# Oinkly 1.1 Release Plan

**Build name:** Laser Focused, You Idiot

## Overview

Version 1.1 is mostly about the debt war plan, plus receipt verification, PDF letterhead, and general polish. In-app humor stays Mel Brooks inspired, mainly Spaceballs.

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
- [ ] Later: fill in a blank transaction from a receipt automatically, learn categories as well as payees, and check receipts from the register's Add Receipt link and from Pay a Bill.

## Feature 3: PDF Letterhead ✅ Done

- [x] Printed and exported PDFs get a letterhead generated automatically, with an image, across the top of the first page.
- [x] Decided: both. By default it is the Oinkly Budget pig and name. Settings ▸ General ▸ Letterhead can switch to your own logo, name and a line of details (for small businesses), or turn it off. The logo is kept on the Mac only, outside backups.

## Maybe: Paycheck Stub Tracking

- Might be cut from 1.1.
- Scan stubs or enter them by hand to keep a running record of pay and withholding.
- Tracking only, with no tax estimates or refund calculations, so it isn't a regulated tax service.

## General

- Tweaks and bug fixes throughout the app.

## Future Releases

- **Ludicrous Speed:** planned as the 2.0 release name, but might move up to 1.2 depending on features.
