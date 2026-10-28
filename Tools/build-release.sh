#!/bin/bash
# Builds the disk image for a release from the notarized app, and takes its SHA-256.
#
#     Tools/build-release.sh 1.1
#
# Expects release-build/<version>/export/OinklyBudget.app (the app exported from Xcode's Organizer, notarized). Checks that it is notarized
# and stapled, then makes release-build/<version>/Oinkly-Budget-<version>.dmg with the pig background (window 600x400, the app at 150,190 and
# the Applications link at 450,190, as in the release checklist) and writes the SHA-256 beside it. The pig background is in
# release-build/dmg-assets/, and the layout numbers are the variables just below, so change them there to adjust how the window looks.
# Add --check to only run the checks and build nothing, or --allow-unnotarized to try it on an app that is not notarized yet. Never rebuild a .dmg after it is uploaded or signed: its SHA-256
# and signature change.
set -euo pipefail

version="${1:-}"; flag="${2:-}"
[ -n "$version" ] || { echo "usage: Tools/build-release.sh <version> [--check | --allow-unnotarized]"; exit 1; }
root="$(cd "$(dirname "$0")/.." && pwd)"
folder="$root/release-build/$version"
app="$folder/export/OinklyBudget.app"
dmg="$folder/Oinkly-Budget-$version.dmg"
background="$root/release-build/dmg-assets/background.tiff"
creator="$HOME/create-dmg/create-dmg"

# How the disk image window looks.
volume_name="Oinkly Budget"
window_size=(600 400)
app_icon_position=(150 190)
drop_link_position=(450 190)

[ -d "$app" ] || { echo "Can't find $app. Export the notarized app from Xcode's Organizer into that folder first."; exit 1; }
[ -f "$background" ] || { echo "Can't find the pig background at $background"; exit 1; }
[ -x "$creator" ] || { echo "Can't find create-dmg at $creator"; exit 1; }
[ ! -e "$dmg" ] || { echo "$dmg already exists. Never rebuild a disk image after it is uploaded or signed; delete it yourself if you really mean to."; exit 1; }

built=$(defaults read "$app/Contents/Info" CFBundleShortVersionString)
build=$(defaults read "$app/Contents/Info" CFBundleVersion)
echo "App: version $built, build $build"
[ "$built" = "$version" ] || { echo "The app is version $built, not $version."; exit 1; }

# Work on a clean copy in a temporary folder. A copy that has been through Finder, or sits in a folder that iCloud Drive syncs, picks up extra
# attributes (Finder information and iCloud's markers) on the folders inside the app, which make the strict signature check fail. They are not
# part of the signature, so they are cleared from the copy, which is what goes into the disk image.
stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT
cp -R "$app" "$stage/OinklyBudget.app"
xattr -cr "$stage/OinklyBudget.app"

if [ "$flag" != "--allow-unnotarized" ]; then
    codesign --verify --deep --strict "$stage/OinklyBudget.app" || { echo "The signature does not check out."; exit 1; }
    spctl -a -vv "$stage/OinklyBudget.app" 2>&1 | tee /dev/stderr | grep -q "Notarized Developer ID" || { echo "The app is not notarized. Export it as Notarized from Organizer."; exit 1; }
    xcrun stapler validate "$stage/OinklyBudget.app" || { echo "The notarization ticket is not stapled to the app."; exit 1; }
fi

if [ "$flag" = "--check" ]; then
    echo "All checks passed: the app is version $built, build $build, signed, notarized and stapled."
    exit 0
fi

"$creator" --volname "$volume_name" --background "$background" --window-size "${window_size[@]}" \
    --icon "OinklyBudget.app" "${app_icon_position[@]}" --app-drop-link "${drop_link_position[@]}" "$dmg" "$stage"

( cd "$folder" && shasum -a 256 "$(basename "$dmg")" | tee "$(basename "$dmg").sha256" )
echo "Made $dmg"
