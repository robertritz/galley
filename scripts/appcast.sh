#!/bin/bash
# Adds a release to appcast.xml, the list of versions Galley's updater (Sparkle)
# reads. Signs the DMG with the update key in this Mac's keychain.
#
#   scripts/appcast.sh 0.3.1 5 dist/Galley-0.3.1.dmg    # version, build number, DMG
#
# The notes come from that version's section of CHANGELOG.md (if any), and the download URL
# is the DMG attached to the GitHub release v<version>.
set -euo pipefail

VERSION="${1:?usage: scripts/appcast.sh <version> <build> <dmg>}"
BUILD="${2:?give the build number (CURRENT_PROJECT_VERSION)}"
DMG="${3:?give the path to the DMG}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

grep -q "<sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>" appcast.xml &&
  { echo "appcast.xml already has $VERSION."; exit 1; }

# Sparkle's signing tool comes with the Swift package; fetch it once into a cache.
PACKAGES="$HOME/Library/Caches/GalleyPackages"
BIN="$PACKAGES/artifacts/sparkle/Sparkle/bin"
if [[ ! -x "$BIN/sign_update" ]]; then
  echo "==> Fetching Sparkle's tools"
  xcodebuild -resolvePackageDependencies -project Galley.xcodeproj -scheme Galley \
    -clonedSourcePackagesDirPath "$PACKAGES" -quiet
fi

SIGNATURE=$("$BIN/sign_update" --account galley "$DMG")   # sparkle:edSignature="…" length="…"
# The version's section of the changelog, as Markdown (Sparkle renders it natively).
NOTES=$(awk -v v="$VERSION" '/^## /{p=(index($0, "## " v " ")==1); next} p' CHANGELOG.md | sed -e '/./,$!d')
URL="https://github.com/robertritz/galley/releases/download/v$VERSION/$(basename "$DMG")"

export ITEM="    <item>
      <title>Galley $VERSION</title>
      <pubDate>$(LC_ALL=C date -u '+%a, %d %b %Y %H:%M:%S +0000')</pubDate>
      <sparkle:version>$BUILD</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>15.0</sparkle:minimumSystemVersion>
      <description sparkle:format=\"markdown\"><![CDATA[
$NOTES
      ]]></description>
      <enclosure url=\"$URL\" type=\"application/octet-stream\" $SIGNATURE/>
    </item>
"
perl -0pi -e 's/(<!-- Releases, newest first[^\n]*\n)/$1$ENV{ITEM}/' appcast.xml
echo "==> appcast.xml: Galley $VERSION (build $BUILD)"
