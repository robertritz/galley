# Releasing Galley

Galley ships as a signed, notarised DMG from GitHub Releases. `scripts/release.sh`
does the whole thing; it needs three things set up once.

## One-time setup

1. **Developer ID certificate.** In Xcode: Settings → Accounts → select your Apple ID →
   *Manage Certificates…* → **+** → *Developer ID Application*. (Your existing
   *Apple Development* certificate is only for running builds on your own Mac.)

2. **Notarisation credentials.** Make an app-specific password at
   [account.apple.com](https://account.apple.com) → Sign-In and Security →
   App-Specific Passwords, then store it in your keychain:

   ```bash
   xcrun notarytool store-credentials galley-notary --apple-id YOUR_APPLE_ID --team-id J5NT99LSV6
   ```

3. **The update key.** Galley updates itself with [Sparkle](https://sparkle-project.org),
   and only installs releases signed with Galley's update key. The private half lives in
   your login keychain (account `galley`); the public half is `SUPublicEDKey` in
   `project.yml`. **Keep a backup** in your password manager: without it, installed
   copies can never be updated again. Sparkle's tools are in
   `~/Library/Caches/GalleyPackages/artifacts/sparkle/Sparkle/bin/` after a release (or
   any `scripts/appcast.sh` run):

   ```bash
   generate_keys --account galley -x galley-update-key.txt   # export, then store it safely and delete the file
   generate_keys --account galley -f galley-update-key.txt   # on a new Mac: import it
   ```

## Each release

As you work, note user-facing changes under `## Unreleased` at the top of
[CHANGELOG.md](CHANGELOG.md): a one-line summary, then `- ` items.

Then one command does everything: bumps the version in `project.yml`, builds, signs,
notarises and staples the DMG, renames the Unreleased section to the version and
today's date, commits, tags, publishes the GitHub release with those notes, and finally
adds the release to `appcast.xml` (signed with the update key) and pushes it, so
installed copies of Galley offer the update.

```bash
scripts/publish.sh 0.3.0
```

Pass notes as a second argument (text or a file) to use them for the GitHub release
instead. Start a new `## Unreleased` section for the next version's changes.

To do it by hand instead: bump `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in
`project.yml`, run `scripts/release.sh` (the DMG lands in `dist/`),
`gh release create v0.3.0 dist/Galley-0.3.0.dmg`, then
`scripts/appcast.sh 0.3.0 <build number> dist/Galley-0.3.0.dmg` and commit and push
`appcast.xml`.

`SKIP_NOTARIZE=1 scripts/release.sh` makes a signed DMG without notarising, which is
handy for checking the build quickly. Other Macs will warn about it.

## Updates

Galley checks `appcast.xml` on `main` (via raw.githubusercontent.com) once a day, and
from **Galley → Check for Updates…**. Only release builds check; builds run from Xcode
don't. To try an update by hand, launch a release build with `GALLEY_FEED_URL` set to
another appcast (say, one served from `localhost`).

## The website

[galley.robertritz.com](https://galley.robertritz.com) is a Micro.blog single-page
website. Its whole page is the theme template `layouts/index.html`, built from
`site/index.html` with `site/build.sh`; images load from `site/img/` in this repo via
jsDelivr. The build fills in the version line and the changelog section from the
released entries in CHANGELOG.md (`site/changelog.pl`), and the page refreshes both from
CHANGELOG.md on GitHub when it loads, so releases show up without touching the site. The
download button points at `releases/latest/download/Galley.dmg`, which always serves the
newest DMG. Rebuild and paste `site/build/index.html` into the template only when the
page itself changes.
