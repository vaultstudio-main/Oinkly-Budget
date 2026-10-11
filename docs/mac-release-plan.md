# Mac-only first release (iPhone and iPad later)

The iPhone and iPad code stays in the project and keeps building. Only the Mac build is archived and submitted.

## Why this is fine
- The Mac archive is a macOS build. iOS-only code sits behind `#if os(iOS)` and is not in it.
- App Store Connect only lists a platform once you add it to the app and upload a build for it.
- Keep bundle id `vault.Piggybank` and one app record. When iOS is ready, add the iOS platform to that same record.
  Same bundle id on both gives universal purchase (buy once, get both). Decide pricing before you ship the Mac app.

## Wording switch
`Piggybank/Logic/ReleaseInfo.swift` has `mobileReleased = false`. While it is false, the Mac app's About text and
Release Notes don't mention iPhone or iPad. iOS builds always show everything, so TestFlight testing is unaffected.
Flip it to `true` in the iOS release.

## Before submitting the Mac build
- [ ] App Store Connect: create the app record, macOS platform only. Don't add iOS yet.
- [ ] Listing text and screenshots mention only the Mac.
- [x] Release notes: the "Fixes" list is gone; 1.0 opens with a "Why it's different" highlights section.
- [ ] Version `1.0`, build `1`, bumped for each upload (project settings; Release Notes window reads them).
- [ ] Archive the Mac scheme with the macOS destination, validate, upload.
- [ ] Sandbox entitlements: app sandbox + user-selected files (read/write) are what the app needs. Confirm in the archive.
- [ ] Privacy answers: nothing collected, nothing leaves the device (true while sync is off, see icloud-sync-plan.md).
- [ ] Notifications: bill reminders ask for permission only when there are reminders to schedule.
- [ ] Take a `.pig` backup of your own data before installing a release build over a dev build.

## Later: iPhone and iPad
- Work the mobile issues behind the scenes with TestFlight, on the same code base.
- Add the iOS platform to the existing app record, flip `ReleaseInfo.mobileReleased`, ship.
- The home screen icon name is **Piggy Mobile**, already set: `INFOPLIST_KEY_CFBundleDisplayName[sdk=iphone*]` in the
  project's build settings. It is short on purpose, because iOS cuts long icon labels at roughly 12 characters
  ("Piggybank Mobile" would show as "Piggybank M…"). The Mac name is a separate setting. The App Store listing name is set
  in App Store Connect, not here. Check the label on a device.
- Re-check copy that says "Mac" only (ReleaseInfo.devicesPhrase handles About; the listing is manual).
