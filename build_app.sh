#!/bin/bash
# Builds Focado.app: compiles release binary, assembles the bundle, ad-hoc signs it.
set -euo pipefail
cd "$(dirname "$0")"

APP="Focado.app"
BIN_NAME="Focado"

echo "-- building release binary --"
swift build -c release

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp ".build/release/$BIN_NAME" "$APP/Contents/MacOS/$BIN_NAME"
cp "Info.plist" "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

if [ -f "AppIcon.icns" ]; then
    cp "AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
else
    echo "warning: AppIcon.icns not found at project root, bundling without a custom icon"
fi

echo "-- ad-hoc codesigning --"
codesign --force --deep --sign - "$APP"
codesign --verify --verbose "$APP"

echo "-- done: $APP --"
