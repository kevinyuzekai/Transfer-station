#!/usr/bin/env bash
# Package the built .app into a styled, compressed DMG:
#   拖入 Applications 的经典布局 + 自定义背景图 + 卷图标。
# 若 Finder 布局步骤不可用，会自动回退为默认布局，仍然产出可用的 DMG。
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$(pwd)"

APP_NAME="FileTransferStation"
DISPLAY_NAME="文件中转站"
VERSION="${VERSION:-1.1.0}"

DIST="$ROOT/dist"
APP="$DIST/$APP_NAME.app"
DMG="$DIST/$APP_NAME-$VERSION.dmg"
RW_DMG="$DIST/$APP_NAME-rw.dmg"
STAGE="$ROOT/.dmg-stage"
MOUNT="$ROOT/.dmg-mount"

if [ ! -d "$APP" ]; then
  echo "!! $APP not found; run scripts/build-app.sh first" >&2
  exit 1
fi

echo "==> staging"
rm -rf "$STAGE" "$MOUNT"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

echo "==> hdiutil create (UDRW)"
rm -f "$RW_DMG" "$DMG"
hdiutil create -volname "$DISPLAY_NAME" -srcfolder "$STAGE" -ov -format UDRW "$RW_DMG" >/dev/null

echo "==> arrange window"
mkdir -p "$MOUNT"
# 注意：不能加 -nobrowse，否则 Finder 看不到该卷，AppleScript 无法按名称定位磁盘。
if hdiutil attach "$RW_DMG" -mountpoint "$MOUNT" -noautoopen >/dev/null; then
  sleep 2
  BG="$ROOT/assets/dmg-background.png"
  BG2X="$ROOT/assets/dmg-background@2x.png"
  if [ -f "$BG" ]; then
    mkdir -p "$MOUNT/.background"
    cp "$BG" "$MOUNT/.background/background.png"
    if [ -f "$BG2X" ]; then cp "$BG2X" "$MOUNT/.background/background@2x.png"; fi
  fi
  if [ -f "$APP/Contents/Resources/AppIcon.icns" ]; then
    cp "$APP/Contents/Resources/AppIcon.icns" "$MOUNT/.VolumeIcon.icns"
  fi

  set +e
  osascript <<APPLESCRIPT
tell application "Finder"
  tell disk "$DISPLAY_NAME"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {200, 120, 860, 560}
    set opts to the icon view options of container window
    set arrangement of opts to not arranged
    set icon size of opts to 120
    set text size of opts to 12
    set background picture of opts to file ".background:background.png"
    set position of item "$APP_NAME.app" of container window to {150, 210}
    set position of item "Applications" of container window to {510, 210}
    update without registering applications
    delay 1
    close
  end tell
end tell
APPLESCRIPT
  LAYOUT_RC=$?
  set -e
  if [ "$LAYOUT_RC" -ne 0 ]; then
    echo "!! Finder 布局失败 (rc=$LAYOUT_RC)，保留默认布局"
  fi

  sync
  hdiutil detach "$MOUNT" >/dev/null || hdiutil detach "$MOUNT" -force >/dev/null || true
else
  echo "!! 无法挂载读写镜像，跳过布局"
fi

echo "==> hdiutil convert (UDZO)"
hdiutil convert "$RW_DMG" -format UDZO -o "$DMG" -ov >/dev/null
rm -f "$RW_DMG"
rm -rf "$STAGE" "$MOUNT"

# 让挂载后的磁盘使用自定义卷图标
if [ -f "$APP/Contents/Resources/AppIcon.icns" ] && command -v SetFile >/dev/null 2>&1; then
  SetFile -a C "$DMG" || true
fi

echo "==> dmg ready: $DMG"
