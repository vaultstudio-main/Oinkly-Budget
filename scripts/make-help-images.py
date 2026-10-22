#!/usr/bin/env python3
"""Turns the raw screenshots the app takes of itself into the images Help, the website and the App Store use.

Take the raw pictures first (debug build, never your real data):
    OinklyBudget -screenshotMode YES -screenshotDir /Users/Shared/OinklyBudget/shots -appearance light
Then run this from the repository folder:
    python3 scripts/make-help-images.py /Users/Shared/OinklyBudget/shots

It uses only macOS's own `sips`. Help images go into OinklyBudget/OinklyBudget/Assets.xcassets as Help-*.imageset, website images
into docs/website-images (the website itself is kept outside this repository), and the App Store set into docs/app-store-screenshots.
"""
import json
import shutil
import subprocess
import sys
from pathlib import Path

root = Path(__file__).resolve().parent.parent
assets = root / "OinklyBudget/OinklyBudget/Assets.xcassets"
web = root / "docs/website-images"
store = root / "docs/app-store-screenshots"
raw = Path(sys.argv[1] if len(sys.argv) > 1 else "/Users/Shared/OinklyBudget/shots")
wide = Path(sys.argv[2]) if len(sys.argv) > 2 else None

# (asset name, raw picture, widest pixels, crop as (top, left, height, width) in the picture's own pixels or None)
# The pages were taken at 3200 x 2000 pixels.
HELP = [
    ("Help-welcome", "page-summary", 1800, None),
    ("Help-sidebar", "page-summary", 700, (0, 0, 2000, 664)),
    ("Help-status-bar", "page-summary", 1800, (1936, 664, 64, 2536)),
    ("Help-summary", "page-summary", 1800, None),
    ("Help-priority-bills", "page-summary", 1800, (740, 636, 350, 2500)),
    ("Help-summary-lower", "page-summary-lower", 1800, None),
    ("Help-transactions", "page-transactions", 1800, None),
    ("Help-reports", "page-reports", 1800, None),
    ("Help-reports-spending", "page-reports-spending", 1800, None),
    ("Help-reports-net-worth", "page-reports-net-worth", 1800, None),
    ("Help-reports-debt", "page-reports-debt-loans", 1800, None),
    ("Help-liabilities", "page-liabilities", 1800, None),
    ("Help-investments", "page-investments", 1800, None),
    ("Help-goals", "page-planning", 1800, None),
    ("Help-budgets", "page-budgets", 1800, None),
    ("Help-manage-accounts-page", "page-manage-accounts", 1800, None),
    ("Help-bills", "page-bills", 1800, None),
    ("Help-recurring", "page-recurring", 1800, None),
    ("Help-register", "account-checking", 1800, None),
    ("Help-split-register", "page-transactions-split", 1800, None),
    ("Help-recurring-pending", "page-transactions", 1800, None),
    ("Help-tags-register", "page-transactions-tags", 1800, None),
    ("Help-account-toolbar", "account-checking", 1400, (60, 660, 150, 2500)),
    ("Help-card-details", "account-card", 1800, None),
    ("Help-loan-details", "account-loan", 1800, None),
    ("Help-mortgage-details", "account-mortgage", 1800, None),
    ("Help-auto-loan-details", "account-auto-loan", 1800, None),
    ("Help-savings-details", "account-savings", 1800, None),
    ("Help-goal-section", "account-savings", 1800, None),
    ("Help-cash-page", "account-cash", 1800, None),
    ("Help-brokerage", "account-brokerage", 1800, None),
    ("Help-edit-account", "sheet-edit-account-checking", 1000, None),
    ("Help-opening-balance-edit", "sheet-edit-account-checking", 1000, None),
    ("Help-edit-transaction", "sheet-edit-split", 1000, None),
    ("Help-tags", "sheet-edit-tags", 1000, None),
    ("Help-export", "sheet-export-pdf", 1000, None),
    ("Help-export-csv", "sheet-export-csv", 1000, None),
    ("Help-import", "sheet-import", 1200, None),
    ("Help-import-mapping", "sheet-import-mapping", 1200, None),
    ("Help-new-bill", "sheet-add-bill", 1000, None),
    ("Help-edit-bill", "sheet-edit-bill", 1000, None),
    ("Help-recurring-edit", "sheet-add-rule", 1000, None),
    ("Help-make-recurring", "sheet-make-recurring", 1000, None),
    ("Help-goal-edit", "sheet-add-goal", 1000, None),
    ("Help-goal-detail", "sheet-goal-detail", 1000, None),
    ("Help-new-transaction", "win-new-transaction", 1000, None),
    ("Help-autofill", "win-new-transaction-autofill", 1000, None),
    ("Help-split", "win-new-transaction-split", 1000, None),
    ("Help-detail-window", "win-detail-split", 1000, None),
    ("Help-split-detail", "win-detail-split", 1000, None),
    ("Help-receipt", "register-wide", 1800, None),
    ("Help-card-charge", "win-card-charge", 1000, None),
    ("Help-atm-withdrawal", "win-atm", 1000, None),
    ("Help-transfer", "win-transfer", 1000, None),
    ("Help-pay-bill", "win-pay-bill", 1000, None),
    ("Help-update-price", "win-update-price", 1000, None),
    ("Help-cash-transaction", "win-new-cash", 1000, None),
    ("Help-manage-accounts", "set-accounts", 1000, None),
    ("Help-categories", "set-categories", 1000, None),
    ("Help-tags-settings", "set-tags", 1000, None),
    ("Help-cleanup", "set-cleanup", 1000, None),
    ("Help-backup", "set-data", 1000, None),
    ("Help-reminders-settings", "set-reminders", 1000, None),
    ("Help-general-settings", "set-general", 1000, None),
    ("Help-payment-methods", "set-payment-methods", 1000, None),
    ("Help-menu-bar", "menubar-popup", 800, None),
    ("Help-widget-large", "widget-large", 800, None),
    ("Help-widget-medium", "widget-medium", 1000, None),
    ("Help-widget-small", "widget-small", 500, None),
]

# Website pictures (1600 wide).
WEB = [
    ("summary.png", "page-summary"), ("transactions.png", "page-transactions"), ("bills.png", "page-bills"),
    ("recurring.png", "page-recurring"), ("register.png", "account-checking"), ("card.png", "account-card"),
    ("mortgage.png", "account-mortgage"), ("savings.png", "account-savings"), ("reports.png", "page-reports-spending"),
    ("liabilities.png", "page-liabilities"), ("investments.png", "page-investments"), ("planning.png", "page-planning"),
    ("budgets.png", "page-budgets"), ("cash.png", "account-cash"), ("brokerage.png", "account-brokerage"),
]
WEB_SMALL = [
    ("split.png", "win-new-transaction-split", 900), ("import.png", "sheet-import", 1100), ("export.png", "sheet-export-pdf", 900),
    ("edit-transaction.png", "sheet-edit-split", 900), ("tags.png", "sheet-edit-tags", 900), ("menu-bar.png", "menubar-popup", 700),
    ("widget-large.png", "widget-large", 700), ("widget-medium.png", "widget-medium", 900), ("widget-small.png", "widget-small", 450),
    ("add-bill.png", "sheet-add-bill", 900), ("add-recurring.png", "sheet-add-rule", 900), ("goal.png", "sheet-add-goal", 900),
    ("pay-bill.png", "win-pay-bill", 900), ("settings-reminders.png", "set-reminders", 900),
]

# App Store: exactly 2880 x 1800.
STORE = [
    ("01-summary.png", "page-summary"), ("02-bills.png", "page-bills"), ("03-recurring.png", "page-recurring"),
    ("04-checking.png", "account-checking"), ("05-reports.png", "page-reports"), ("06-planning.png", "page-planning"),
    ("07-card.png", "account-card"), ("08-budgets.png", "page-budgets"), ("09-investments.png", "page-investments"),
    ("10-transactions.png", "page-transactions"),
]


def source(name):
    # One picture is taken in a wider window so the Receipt column shows.
    if name == "register-wide":
        return wide / "account-checking.png" if wide and (wide / "account-checking.png").exists() else None
    for folder in (raw, wide):
        if folder and (folder / f"{name}.png").exists():
            return folder / f"{name}.png"
    return None


def sips(*args):
    subprocess.run(["sips", *map(str, args)], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def make(src, dest, widest, crop=None, exact=None):
    dest.parent.mkdir(parents=True, exist_ok=True)
    if dest.exists():
        dest.unlink()
    shutil.copyfile(src, dest)
    if crop:
        top, left, height, width = crop
        sips("-c", height, width, "--cropOffset", top, left, dest)
    if exact:
        sips("--resampleHeightWidth", exact[1], exact[0], dest)
    else:
        sips("-Z", widest, dest)


missing = []
for name, picture, widest, crop in HELP:
    src = source(picture)
    if not src:
        missing.append(picture)
        continue
    folder = assets / f"{name}.imageset"
    make(src, folder / f"{name}.png", widest, crop)
    (folder / "Contents.json").write_text(json.dumps(
        {"images": [{"filename": f"{name}.png", "idiom": "universal"}], "info": {"author": "xcode", "version": 1}}, indent=2) + "\n")
for name, picture in WEB:
    src = source(picture)
    if src:
        make(src, web / name, 1600)
    else:
        missing.append(picture)
for name, picture, widest in WEB_SMALL:
    src = source(picture)
    if src:
        make(src, web / name, widest)
    else:
        missing.append(picture)
if store.exists():
    for old in store.glob("*.png"):
        old.unlink()
for name, picture in STORE:
    src = source(picture)
    if src:
        make(src, store / name, 2880, exact=(2880, 1800))
    else:
        missing.append(picture)
print("missing:", sorted(set(missing)))

# The folder may sync with iCloud, which can leave "name 2.png" conflict copies of files written twice in a row.
import re
import time
time.sleep(5)
for folder in (assets, web, store):
    for stray in folder.rglob("*.png"):
        if re.search(r" \d+\.png$", stray.name):
            stray.unlink()
