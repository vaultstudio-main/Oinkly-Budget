#!/usr/bin/env python3
"""Puts the app's screenshots into the Help window's pictures (the `Help-...` image sets in Assets.xcassets).

Take the pictures first, with the demo data (a Debug build, which writes one PNG for each page, window, sheet and Settings tab):

    open -n <OinklyBudget.app> --args -screenshotMode YES -screenshotFresh YES -screenshotDir /Users/Shared/OinklyBudget/shots -appearance light

Then run this, which resizes each picture the way the Help window expects and replaces the matching image set (or makes a new one):

    python3 Tools/install-help-pictures.py /Users/Shared/OinklyBudget/shots

Whole pages are 1800 pixels wide. Windows, sheets and Settings tabs are scaled down so their longest side is at most 1000 pixels (a few, listed
below, are different). A few pictures are crops of a page. Uses only sips, which comes with macOS.
"""
import json, os, shutil, subprocess, sys, tempfile

ASSETS = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "OinklyBudget", "OinklyBudget", "Assets.xcassets")

TITLE_BAR = 104
# Pages that are a window of their own, which has no title bar to trim.
OWN_WINDOW = {"page-manage-accounts", "page-manage-accounts-archived"}

# Help picture <- picture from the tour. Whole pages, 1800 wide.
PAGES = {
    "Help-welcome": "page-summary", "Help-summary": "page-summary", "Help-summary-lower": "page-summary-lower",
    "Help-transactions": "page-transactions", "Help-register": "account-checking", "Help-recurring-pending": "account-checking",
    "Help-split-register": "page-transactions-split", "Help-tags-register": "page-transactions-tags",
    "Help-bills": "page-bills", "Help-recurring": "page-recurring", "Help-budgets": "page-budgets",
    "Help-reports": "page-reports", "Help-reports-spending": "page-reports-spending", "Help-reports-net-worth": "page-reports-net-worth",
    "Help-reports-debt": "page-reports-debt-loans", "Help-reports-budgets": "page-reports-budgets",
    "Help-goals": "page-planning", "Help-goal-section": "account-savings", "Help-liabilities": "page-liabilities",
    "Help-investments": "page-investments", "Help-brokerage": "account-brokerage", "Help-card-details": "account-card",
    "Help-savings-details": "account-savings", "Help-cash-page": "account-cash", "Help-loan-details": "account-loan",
    "Help-mortgage-details": "account-mortgage", "Help-auto-loan-details": "account-auto-loan",
    "Help-manage-accounts-page": "page-manage-accounts", "Help-month-outlook": "page-month-outlook",
    # New in 1.1
    "Help-war-plan": "page-war-plan", "Help-debt-war-plan": "page-debt-war-plan", "Help-savings-war-plan": "page-savings-war-plan",
    "Help-planning-archive": "page-planning-archive", "Help-accounts-archived": "page-manage-accounts-archived",
}

# Windows, sheets, Settings tabs and the menu bar pop-up: longest side at most 1000.
WINDOWS = {
    "Help-manage-accounts": "set-accounts", "Help-edit-account": "sheet-edit-account-checking",
    "Help-opening-balance-edit": "sheet-edit-account-checking", "Help-atm-withdrawal": "win-atm", "Help-cash-transaction": "win-new-cash",
    "Help-card-charge": "win-card-charge", "Help-new-transaction": "win-new-transaction", "Help-edit-transaction": "sheet-edit-tags",
    "Help-detail-window": "win-detail-split", "Help-split": "win-new-transaction-split", "Help-split-detail": "win-detail-split",
    "Help-tags": "sheet-edit-tags", "Help-tags-settings": "set-tags", "Help-transfer": "win-transfer", "Help-import": "sheet-import",
    "Help-import-mapping": "sheet-import-mapping", "Help-export": "sheet-export-pdf", "Help-export-csv": "sheet-export-csv",
    "Help-autofill": "win-new-transaction-autofill", "Help-cleanup": "set-cleanup", "Help-new-bill": "sheet-add-bill",
    "Help-edit-bill": "sheet-edit-bill", "Help-recurring-edit": "sheet-add-rule", "Help-make-recurring": "sheet-make-recurring",
    "Help-pay-bill": "win-pay-bill", "Help-categories": "set-categories", "Help-goal-edit": "sheet-add-goal",
    "Help-goal-detail": "sheet-goal-detail", "Help-update-price": "win-update-price", "Help-backup": "set-data",
    "Help-menu-bar": "menubar-popup", "Help-reminders-settings": "set-reminders", "Help-widget-large": "widget-large",
    "Help-widget-medium": "widget-medium", "Help-widget-small": "widget-small", "Help-general-settings": "set-general",
    "Help-payment-methods": "set-payment-methods",
    # New in 1.1
    "Help-updates": "set-general",
}

# Wider than the usual 1000: the receipt needs to be read.
WINDOW_SIZES = {"Help-receipt": 1400}
WINDOWS["Help-receipt"] = "win-detail-receipt"

# Crops of a page: asset -> (picture, top, left, height, width, final width), in pixels of the 3200 x 2000 original.
CROPS = {
    "Help-sidebar": ("page-summary", 128, 0, 1808, 600, 232),
    "Help-status-bar": ("page-summary", 1910, 0, 88, 3200, 1800),
    "Help-priority-bills": ("page-summary", 779, 630, 432, 2510, 1800),
    "Help-account-toolbar": ("account-checking", 136, 2050, 80, 1130, 1400),
}


def sips(*args):
    result = subprocess.run(["sips", *args], capture_output=True, text=True)
    if result.returncode != 0:
        sys.exit("sips failed: " + result.stderr + result.stdout)


def size_of(path):
    out = subprocess.run(["sips", "-g", "pixelWidth", "-g", "pixelHeight", path], capture_output=True, text=True).stdout
    width = int(out.split("pixelWidth:")[1].split()[0])
    height = int(out.split("pixelHeight:")[1].split()[0])
    return width, height


def install(asset, source):
    folder = os.path.join(ASSETS, asset + ".imageset")
    os.makedirs(folder, exist_ok=True)
    shutil.copyfile(source, os.path.join(folder, asset + ".png"))
    contents = os.path.join(folder, "Contents.json")
    if not os.path.exists(contents):
        with open(contents, "w") as f:
            json.dump({"images": [{"filename": asset + ".png", "idiom": "universal"}], "info": {"author": "xcode", "version": 1}}, f, indent=2)


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    shots = sys.argv[1]
    work = tempfile.mkdtemp()
    done, missing = 0, []

    def source(name):
        path = os.path.join(shots, name + ".png")
        if not os.path.exists(path):
            return None
        return path

    for asset, name in PAGES.items():
        path = source(name)
        if not path:
            missing.append((asset, name)); continue
        out = os.path.join(work, asset + ".png")
        if name in OWN_WINDOW:
            sips("--resampleWidth", "1800", path, "--out", out)
        else:
            # The top 104 pixels of a page picture are the window's title bar, with its title. Leave them off.
            trimmed = os.path.join(work, asset + "-trim.png")
            width, height = size_of(path)
            # sips ignores a crop that ends exactly at the edge of the picture, so stop a few pixels short of the bottom.
            sips("-c", str(height - TITLE_BAR - 6), str(width), "--cropOffset", str(TITLE_BAR), "0", path, "--out", trimmed)
            sips("--resampleWidth", "1800", trimmed, "--out", out)
        install(asset, out); done += 1
    for asset, name in WINDOWS.items():
        path = source(name)
        if not path:
            missing.append((asset, name)); continue
        out = os.path.join(work, asset + ".png")
        limit = WINDOW_SIZES.get(asset, 1000)
        width, height = size_of(path)
        if max(width, height) > limit:
            sips("-Z", str(limit), path, "--out", out)
        else:
            shutil.copyfile(path, out)
        install(asset, out); done += 1
    for asset, (name, top, left, height, width, final) in CROPS.items():
        path = source(name)
        if not path:
            missing.append((asset, name)); continue
        cropped = os.path.join(work, asset + "-crop.png")
        out = os.path.join(work, asset + ".png")
        sips("-c", str(height), str(width), "--cropOffset", str(top), str(left), path, "--out", cropped)
        sips("--resampleWidth", str(final), cropped, "--out", out)
        install(asset, out); done += 1
    shutil.rmtree(work, ignore_errors=True)
    print(f"Installed {done} pictures.")
    for asset, name in missing:
        print(f"Missing the tour picture {name}.png for {asset}")


main()
