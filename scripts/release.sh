#!/bin/bash
# Builds a signed, notarised Galley DMG ready to share.
#
#   scripts/release.sh            # build, sign, notarise, staple → dist/Galley-<version>.dmg
#   SKIP_NOTARIZE=1 scripts/release.sh   # signed but not notarised (for a quick local check)
#
# One-time setup (see RELEASING.md):
#   1. A "Developer ID Application" certificate in your keychain (Xcode → Settings →
#      Accounts → Manage Certificates → + → Developer ID Application).
#   2. Notarisation credentials stored in the keychain under the profile "galley-notary":
#        xcrun notarytool store-credentials galley-notary \
#          --apple-id you@example.com --team-id J5NT99LSV6
#      (it asks for an app-specific password from account.apple.com).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# Build outside the repo: iCloud-synced folders break code signing.
WORK="${GALLEY_BUILD_DIR:-$HOME/Library/Caches/GalleyRelease}"
PROFILE="${NOTARY_PROFILE:-galley-notary}"
IDENTITY="Developer ID Application"

cd "$ROOT"
command -v xcodegen >/dev/null || { echo "Install XcodeGen: brew install xcodegen"; exit 1; }
security find-identity -v -p codesigning | grep -q "$IDENTITY" || {
  echo "No “$IDENTITY” certificate found. See RELEASING.md, step 1."; exit 1; }

VERSION=$(grep -m1 'MARKETING_VERSION:' project.yml | awk '{print $2}')
echo "==> Galley $VERSION"
rm -rf "$WORK" && mkdir -p "$WORK" dist

echo "==> Generating project"
xcodegen generate --quiet

echo "==> Archiving"
xcodebuild archive \
  -project Galley.xcodeproj -scheme Galley -configuration Release \
  -archivePath "$WORK/Galley.xcarchive" -allowProvisioningUpdates -quiet

echo "==> Exporting with Developer ID"
xcodebuild -exportArchive \
  -archivePath "$WORK/Galley.xcarchive" -exportOptionsPlist scripts/ExportOptions.plist \
  -exportPath "$WORK/export" -allowProvisioningUpdates -quiet
APP="$WORK/export/Galley.app"
codesign --verify --deep --strict "$APP"

echo "==> Making the disk image"
STAGE="$WORK/dmg"
mkdir -p "$STAGE" && cp -R "$APP" "$STAGE/" && ln -s /Applications "$STAGE/Applications"
DMG="$WORK/Galley-$VERSION.dmg"
hdiutil create -volname "Galley $VERSION" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$DMG" -quiet
codesign --sign "$IDENTITY" --timestamp "$DMG"

if [[ "${SKIP_NOTARIZE:-}" != "1" ]]; then
  echo "==> Notarising (this takes a few minutes)"
  xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait
  xcrun stapler staple "$DMG"
  spctl --assess --type open --context context:primary-signature --verbose "$DMG"
fi

cp "$DMG" dist/
echo "==> Done: dist/$(basename "$DMG")"
