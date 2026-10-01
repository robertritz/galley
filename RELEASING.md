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

1. Bump `MARKETING_VERSION` (and `CURRENT_PROJECT_VERSION`) in `project.yml`.
2. Run `scripts/release.sh`. It generates the project, archives, exports with your
   Developer ID, builds the DMG, notarises it and staples the ticket. The result is
   in `dist/`.
3. Make a GitHub release and attach the DMG:

   ```bash
   gh release create v0.2.0 dist/Galley-0.2.0.dmg --title "Galley 0.2.0" --notes "…"
   ```

`SKIP_NOTARIZE=1 scripts/release.sh` makes a signed DMG without notarising, which is
handy for checking the build quickly. Other Macs will warn about it.
