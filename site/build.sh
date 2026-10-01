#!/bin/bash
# Builds the landing page for galley.robertritz.com: fills in the asset URL.
# Images are served from this repo by jsDelivr, so publishing them is a git push.
#
#   site/build.sh            # → site/build/index.html
#   ASSETS=img site/build.sh # local preview with relative images
set -euo pipefail
cd "$(dirname "$0")"
# Pin images to the last commit that changed them: a new image gets a new URL, so
# browsers never show a stale copy (jsDelivr lets them cache files for a week).
IMG_COMMIT=$(git log -1 --format=%H -- img)
ASSETS="${ASSETS:-https://cdn.jsdelivr.net/gh/robertritz/galley@$IMG_COMMIT/site/img}"
mkdir -p build
sed "s#{{ASSETS}}#$ASSETS#g" index.html > build/index.html
echo "site/build/index.html (assets: $ASSETS)"
