#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."
./package_dmg.sh

test -f Focado.dmg

mount_dir="$(mktemp -d)"
trap 'hdiutil detach "$mount_dir" >/dev/null 2>&1 || true; rmdir "$mount_dir"' EXIT
hdiutil attach -readonly -nobrowse -mountpoint "$mount_dir" Focado.dmg >/dev/null

test -x "$mount_dir/Focado.app/Contents/MacOS/Focado"
test -L "$mount_dir/Applications"
codesign --verify --deep --strict "$mount_dir/Focado.app"
