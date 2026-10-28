#!/usr/bin/env python3
"""Adds a release to appcast.xml, the list Sparkle reads to find new versions of Oinkly Budget.

Run it after the .dmg is built and notarized, before publishing the release:

    python3 Tools/update-appcast.py ~/Desktop/Oinkly-Budget-1.1.dmg --version 1.1 --build 10 --notes ~/Desktop/notes-1.1.md

It signs the .dmg with the private Sparkle key in your login Keychain (using ~/sparkle-tools/sign_update), then puts a new entry at the top of
appcast.xml with the download link on the GitHub release, the signature, the size and the release notes (a Markdown file you write, shown inside Sparkle's update window, ending with a link to
the release page). Without --notes the window only links to the release page. Run it again
for the same version to replace that entry. Then commit and push appcast.xml, and upload the .dmg to the release.
"""
import argparse, datetime, email.utils, os, re, subprocess, sys

REPO = "vaultstudio-main/Oinkly-Budget"
SIGN = os.path.expanduser("~/sparkle-tools/sign_update")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("dmg", help="the notarized .dmg for this release")
    ap.add_argument("--version", required=True, help="the version people see, such as 1.1")
    ap.add_argument("--build", required=True, help="the build number (CFBundleVersion); it must be higher than the last release's")
    ap.add_argument("--notes", help="a Markdown file with the release notes to show in the update window")
    ap.add_argument("--min-os", default="15.0", help="the oldest macOS that can run it (default 15.0)")
    ap.add_argument("--download-url", help="a different download address, for testing with a local server")
    ap.add_argument("--appcast", default=os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "appcast.xml"))
    args = ap.parse_args()

    if not os.path.exists(args.dmg):
        sys.exit(f"Can't find {args.dmg}")
    if not os.path.exists(SIGN):
        sys.exit(f"Can't find {SIGN}. Copy sign_update from Sparkle's package into ~/sparkle-tools first.")
    out = subprocess.run([SIGN, args.dmg], capture_output=True, text=True)
    if out.returncode != 0:
        sys.exit("Signing failed:\n" + out.stdout + out.stderr)
    signature = re.search(r'sparkle:edSignature="([^"]+)"', out.stdout)
    length = re.search(r'length="(\d+)"', out.stdout)
    if not signature or not length:
        sys.exit("Couldn't read the signature from sign_update:\n" + out.stdout)

    tag = f"v{args.version}"
    name = os.path.basename(args.dmg)
    release_page = f"https://github.com/{REPO}/releases/tag/{tag}"
    download = args.download_url or f"https://github.com/{REPO}/releases/download/{tag}/{name}"
    link = f"[See the full release notes on GitHub]({release_page})"
    if args.notes:
        notes = open(os.path.expanduser(args.notes), encoding="utf-8").read().strip()
        if "]]>" in notes:
            sys.exit("The notes can't contain ]]>")
        description = f'''<description sparkle:format="markdown"><![CDATA[{notes}\n\n{link}]]></description>'''
    else:
        description = f"""<description><![CDATA[<p>Oinkly Budget {args.version} is ready. <a href="{release_page}">See what's new</a>.</p>]]></description>"""
    item = f"""        <item>
            <title>Version {args.version}</title>
            <pubDate>{email.utils.format_datetime(datetime.datetime.now(datetime.timezone.utc))}</pubDate>
            <sparkle:version>{args.build}</sparkle:version>
            <sparkle:shortVersionString>{args.version}</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>{args.min_os}</sparkle:minimumSystemVersion>
            {description}
            <enclosure url="{download}" sparkle:edSignature="{signature.group(1)}" length="{length.group(1)}" type="application/octet-stream"/>
        </item>
"""
    path = os.path.abspath(args.appcast)
    text = open(path, encoding="utf-8").read()
    # Replace an entry for this version if there is one, then put the new one at the top (newest first).
    text = re.sub(r"\s*<item>(?:(?!</item>).)*?<sparkle:shortVersionString>" + re.escape(args.version) + r"</sparkle:shortVersionString>.*?</item>\n?", "\n", text, flags=re.S)
    text = text.replace("<language>en</language>\n", "<language>en</language>\n" + item, 1)
    open(path, "w", encoding="utf-8").write(text)
    print(f"Added version {args.version} (build {args.build}) to {path}")
    print(f"Download link: {download}")
    print("Now commit and push appcast.xml, and upload the .dmg to the release.")


main()
