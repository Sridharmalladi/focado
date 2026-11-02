#!/bin/bash
# Builds a drag-to-Applications disk image for GitHub Releases.
set -euo pipefail
cd "$(dirname "$0")"

./build_app.sh

staging="$(mktemp -d)"
trap 'rm -rf "$staging"' EXIT

cp -R Focado.app "$staging/Focado.app"
ln -s /Applications "$staging/Applications"
rm -f Focado.dmg

hdiutil create \
  -volname Focado \
  -srcfolder "$staging" \
  -format UDZO \
  -ov \
  Focado.dmg

echo "-- done: Focado.dmg --"
