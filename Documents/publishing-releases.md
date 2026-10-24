# Publishing a release

Built apps (`.dmg` files) are published on **GitHub Releases**, never committed to the repository. A release belongs to a version and can hold files up to 2 GB, so the repository stays small and people get a proper Download link. `.gitignore` keeps `*.dmg` and `*.app` out of Git on purpose.

## Steps

1. In Xcode, set the version and build number (Oinkly Budget 1.0, build 6 is the current one), then **Product ▸ Archive** with the Release configuration. A release build leaves out the debug-only Testing menu and launch tests.
2. Export the app (sign it with your Developer ID and notarize it, so macOS opens it without warnings), and put it in a `.dmg` named like `Oinkly-Budget-1.0-build6.dmg`.
3. Tag the commit that was built, and push the tag:

   ```bash
   git tag -a v1.0-build6 -m "Oinkly Budget 1.0 (build 6)"
   git push origin v1.0-build6
   ```

4. Create the release and attach the disk image (GitHub's `gh` tool, or the **Releases ▸ Draft a new release** page on GitHub):

   ```bash
   gh release create v1.0-build6 Oinkly-Budget-1.0-build6.dmg --title "Oinkly Budget 1.0 (build 6)" --notes-file release-notes.md
   ```

5. Paste the same notes that are in the app under **Help ▸ Release Notes**, and say which macOS versions it needs (macOS 15 or later).

## Good to know

- Add a SHA-256 checksum of the `.dmg` to the release notes (`shasum -a 256 Oinkly-Budget-1.0-build6.dmg`) so people can check their download.
- Keep older releases up. People may want an earlier build, and their links keep working.
- Plans for what comes next belong in this `Documents/` folder.
