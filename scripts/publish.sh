#!/bin/bash
# Bumps the version, builds a notarised DMG and publishes it as a GitHub release.
#
#   scripts/publish.sh 0.3.0                 # notes from CHANGELOG.md's Unreleased section
#   scripts/publish.sh 0.3.0 "What changed in this release"
#   scripts/publish.sh 0.3.0 notes.md        # notes from a file
#
# The Unreleased section of CHANGELOG.md becomes "## 0.3.0 · <today>" in the
# release commit.
#
# Needs a clean working tree on main, plus the setup in RELEASING.md.
set -euo pipefail

VERSION="${1:?usage: scripts/publish.sh <version> [notes or notes-file]}"
NOTES="${2:-}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

[[ -z "$(git status --porcelain)" ]] || { echo "Commit or stash your changes first."; exit 1; }
git rev-parse -q --verify "refs/tags/v$VERSION" >/dev/null && { echo "v$VERSION already exists."; exit 1; }

# The release notes default to the changelog's Unreleased section.
UNRELEASED=$(awk '/^## /{p=($0=="## Unreleased"); next} p' CHANGELOG.md | sed -e '/./,$!d')
if [[ -z "$NOTES" ]]; then
  [[ -n "$UNRELEASED" ]] || { echo "Add notes under \"## Unreleased\" in CHANGELOG.md, or pass them."; exit 1; }
  NOTES="$UNRELEASED"$'\n\nRequires macOS 15 or later. Open the DMG and drag Galley to Applications.'
fi

# If anything fails before the release commit, put the version and changelog back.
trap 'echo "Failed; restoring project.yml and CHANGELOG.md"; git checkout -- project.yml Galley.xcodeproj CHANGELOG.md; exit 1' ERR

if [[ -n "$UNRELEASED" ]]; then
  sed -i '' "s/^## Unreleased\$/## $VERSION · $(LC_ALL=C date '+%-d %B %Y')/" CHANGELOG.md
fi

# Bump the marketing version and the build number.
BUILD=$(( $(grep -m1 'CURRENT_PROJECT_VERSION:' project.yml | awk '{print $2}') + 1 ))
sed -i '' -E "s/^(    MARKETING_VERSION: ).*/\1$VERSION/; s/^(    CURRENT_PROJECT_VERSION: ).*/\1$BUILD/" project.yml
echo "==> Version $VERSION (build $BUILD)"

scripts/release.sh

git add project.yml Galley.xcodeproj CHANGELOG.md
git commit -q -m "Galley $VERSION"
trap - ERR
git tag "v$VERSION"
git push -q origin HEAD "v$VERSION"

if [[ -f "$NOTES" ]]; then NOTES_ARGS=(--notes-file "$NOTES"); else NOTES_ARGS=(--notes "$NOTES"); fi
# Also attach it as plain "Galley.dmg", so .../releases/latest/download/Galley.dmg
# (the website's download button) always gets the newest version.
cp "dist/Galley-$VERSION.dmg" "dist/Galley.dmg"
gh release create "v$VERSION" "dist/Galley-$VERSION.dmg" "dist/Galley.dmg" --title "Galley $VERSION" "${NOTES_ARGS[@]}"
