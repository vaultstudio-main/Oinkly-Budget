# Help screenshots

Every picture in Help, on the website and in the App Store is taken by the app itself from made-up data, so no real
accounts are ever on screen. They are retaken in one go whenever the screens change.

## How to retake them

1. Build the debug app (Xcode, scheme OinklyBudget).
2. Run it with these launch arguments (the `YES` after `-screenshotMode` matters; without it macOS reads the folder
   as a file to open):

   `OinklyBudget -screenshotMode YES -screenshotDir /Users/Shared/OinklyBudget/shots -appearance light`

   It loads the test data into a throwaway data file, sizes the window to 1600 x 1000, visits every page, window, sheet and
   Settings tab, writes a PNG of each (about 80), and quits. It takes about five minutes. Leave the Mac alone while it
   runs: the app brings itself to the front before each picture. The real data file, reminders and widgets are never
   touched, and the Testing menu is left out.
3. For the register with its Receipt column, run once more in a wider window:

   `… -screenshotDir /Users/Shared/OinklyBudget/shots-wide -screenshotOnly account-checking -screenshotWidth 1900`
4. Turn the raw pictures into the final ones:

   `python3 scripts/make-help-images.py /Users/Shared/OinklyBudget/shots /Users/Shared/OinklyBudget/shots-wide`

   That fills `Assets.xcassets` (the `Help-*` image sets Help shows), `docs/website-images` and
   `docs/app-store-screenshots` (the ten App Store pictures, exactly 2880 x 1800).
5. Build again so Help picks up the new images. Delete `/Users/Shared/OinklyBudget/shots*` afterwards.

`-screenshotOnly <prefix>` takes just the pictures whose names start with the prefix, and `-screenshotWidth <points>`
changes the window width.

## Which picture goes under which Help topic

The table is `HelpContent.shotsByTopic` in `Views/HelpWindow.swift`. An asset that has no image yet simply doesn't show.
The mapping from raw picture to Help image is in `scripts/make-help-images.py`.

## What the app cannot take itself (the owner takes these)

| Asset | Shows | How |
|---|---|---|
| (dropped) Help-safety-copy | Finder: Application Support ▸ Backups ▸ Before this update | Not used; the Help text explains it |
| A reminder notification | A bill reminder banner | After Send a Test Notification in Settings ▸ Reminders |
| Widgets on the real desktop | The widget placed on the desktop, and the widget gallery | Edit widgets on the desktop |
| Menus | File, Go and Transaction menus | ⇧⌘4, Space |

Everything else, including the menu bar pop-up and the three widget sizes, is drawn by the app from the test data.
