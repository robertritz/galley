# Releasing Galley

Galley ships as a signed, notarised DMG from GitHub Releases. `scripts/release.sh`
does the whole thing; it needs two things set up once.

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

## Each release

As you work, note user-facing changes under `## Unreleased` at the top of
[CHANGELOG.md](CHANGELOG.md): a one-line summary, then `- ` items.

Then one command does everything: bumps the version in `project.yml`, builds, signs,
notarises and staples the DMG, renames the Unreleased section to the version and
today's date, commits, tags, and publishes the GitHub release with those notes.

```bash
scripts/publish.sh 0.3.0
```

Pass notes as a second argument (text or a file) to use them for the GitHub release
instead. Start a new `## Unreleased` section for the next version's changes.

To do it by hand instead: bump `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in
`project.yml`, run `scripts/release.sh` (the DMG lands in `dist/`), then
`gh release create v0.3.0 dist/Galley-0.3.0.dmg`.

`SKIP_NOTARIZE=1 scripts/release.sh` makes a signed DMG without notarising, which is
handy for checking the build quickly. Other Macs will warn about it.

## The website

[galley.robertritz.com](https://galley.robertritz.com) is a Micro.blog single-page
website. Its whole page is the theme template `layouts/index.html`, built from
`site/index.html` with `site/build.sh`; images load from `site/img/` in this repo via
jsDelivr. The build also fills in the version line and the changelog section from the
released entries in CHANGELOG.md (`site/changelog.pl`). The download button points at
`releases/latest/download/Galley.dmg`, so it never needs a change, but after each
release (or any page change) rebuild and paste `site/build/index.html` into the template
so the version and changelog are current.
