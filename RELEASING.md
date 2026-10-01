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

One command does everything: bumps the version in `project.yml`, builds, signs,
notarises and staples the DMG, commits, tags, and publishes the GitHub release.

```bash
scripts/publish.sh 0.3.0 "What changed in this release"
```

To do it by hand instead: bump `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in
`project.yml`, run `scripts/release.sh` (the DMG lands in `dist/`), then
`gh release create v0.3.0 dist/Galley-0.3.0.dmg`.

`SKIP_NOTARIZE=1 scripts/release.sh` makes a signed DMG without notarising, which is
handy for checking the build quickly. Other Macs will warn about it.

## The website

[galley.robertritz.com](https://galley.robertritz.com) is a Micro.blog single-page
website. Its whole page is the theme template `layouts/index.html`, built from
`site/index.html` with `site/build.sh`; images load from `site/img/` in this repo via
jsDelivr. The download button points at `releases/latest/download/Galley.dmg`, so new
releases don't need a site change. If the page text changes (say, the version line),
rebuild and paste `site/build/index.html` into the template.
