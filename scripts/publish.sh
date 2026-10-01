#!/bin/bash
# Bumps the version, builds a notarised DMG and publishes it as a GitHub release.
#
#   scripts/publish.sh 0.3.0 "What changed in this release"
#   scripts/publish.sh 0.3.0 notes.md        # notes from a file
#
# Needs a clean working tree on main, plus the setup in RELEASING.md.
set -euo pipefail

VERSION="${1:?usage: scripts/publish.sh <version> <notes or notes-file>}"
NOTES="${2:?give release notes as text or a file}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

[[ -z "$(git status --porcelain)" ]] || { echo "Commit or stash your changes first."; exit 1; }
git rev-parse -q --verify "refs/tags/v$VERSION" >/dev/null && { echo "v$VERSION already exists."; exit 1; }

# Bump the marketing version and the build number.
BUILD=$(( $(grep -m1 'CURRENT_PROJECT_VERSION:' project.yml | awk '{print $2}') + 1 ))
sed -i '' -E "s/^(    MARKETING_VERSION: ).*/\1$VERSION/; s/^(    CURRENT_PROJECT_VERSION: ).*/\1$BUILD/" project.yml
echo "==> Version $VERSION (build $BUILD)"

scripts/release.sh

git add project.yml
git commit -q -m "Galley $VERSION"
git tag "v$VERSION"
git push -q origin HEAD "v$VERSION"

if [[ -f "$NOTES" ]]; then NOTES_ARGS=(--notes-file "$NOTES"); else NOTES_ARGS=(--notes "$NOTES"); fi
gh release create "v$VERSION" "dist/Galley-$VERSION.dmg" --title "Galley $VERSION" "${NOTES_ARGS[@]}"
