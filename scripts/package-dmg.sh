#!/usr/bin/env bash
# Package the built .app into a compressed DMG with an /Applications shortcut.
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$(pwd)"

APP_NAME="FileTransferStation"
DISPLAY_NAME="文件中转站"
VERSION="${VERSION:-1.0.0}"

DIST="$ROOT/dist"
APP="$DIST/$APP_NAME.app"
DMG="$DIST/$APP_NAME-$VERSION.dmg"
STAGE="$ROOT/.dmg-stage"

if [ ! -d "$APP" ]; then
  echo "!! $APP not found; run scripts/build-app.sh first" >&2
  exit 1
fi

echo "==> staging"
rm -rf "$STAGE"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

echo "==> hdiutil create"
rm -f "$DMG"
hdiutil create -volname "$DISPLAY_NAME" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
rm -rf "$STAGE"

echo "==> dmg ready: $DMG"
