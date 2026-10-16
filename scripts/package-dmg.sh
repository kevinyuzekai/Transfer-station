#!/usr/bin/env bash
# Package the built .app into a styled, compressed DMG:
#   拖入 Applications 的经典布局 + 自定义背景图 + 卷图标。
# 若 Finder 布局步骤不可用（例如无图形会话的环境），会自动回退为默认布局，
# 仍然产出可用的 DMG。
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$(pwd)"

APP_NAME="FileTransferStation"
DISPLAY_NAME="文件中转站"
VERSION="${VERSION:-1.1.0}"

# 布局阶段先用 ASCII 卷名（osascript 里避免非 ASCII 字面量），完成后再改回中文名。
LAYOUT_NAME="FileTransferStation"

DIST="$ROOT/dist"
APP="$DIST/$APP_NAME.app"
DMG="$DIST/$APP_NAME-$VERSION.dmg"
RW_DMG="$DIST/$APP_NAME-rw.dmg"
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

echo "==> hdiutil create (UDRW)"
rm -f "$RW_DMG" "$DMG"
hdiutil create -volname "$LAYOUT_NAME" -srcfolder "$STAGE" -ov -format UDRW "$RW_DMG" >/dev/null

echo "==> arrange window"
ATTACH_OUT="$(hdiutil attach "$RW_DMG" -readwrite -noverify -noautoopen)"
DEV="$(printf '%s\n' "$ATTACH_OUT" | awk '/^\/dev\/disk/ {print $1; exit}')"
MOUNT_DIR="$(printf '%s\n' "$ATTACH_OUT" | awk '/\/Volumes\// {print $NF}' | tail -1)"

if [ -n "$MOUNT_DIR" ] && [ -d "$MOUNT_DIR" ]; then
  sleep 2
  BG="$ROOT/assets/dmg-background.png"
  BG2X="$ROOT/assets/dmg-background@2x.png"
  if [ -f "$BG" ]; then
    mkdir -p "$MOUNT_DIR/.background"
    cp "$BG" "$MOUNT_DIR/.background/background.png"
    if [ -f "$BG2X" ]; then cp "$BG2X" "$MOUNT_DIR/.background/background@2x.png"; fi
  fi
  if [ -f "$APP/Contents/Resources/AppIcon.icns" ]; then
    cp "$APP/Contents/Resources/AppIcon.icns" "$MOUNT_DIR/.VolumeIcon.icns"
  fi

  set +e
  osascript <<APPLESCRIPT
tell application "Finder"
  tell disk "$LAYOUT_NAME"
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

  # 卷名改回中文展示名
  diskutil rename "$MOUNT_DIR" "$DISPLAY_NAME" >/dev/null 2>&1 \
    || echo "!! 卷名重命名失败，保留 $LAYOUT_NAME"

  sync
else
  echo "!! 未能定位挂载点，跳过布局"
fi

if [ -n "$DEV" ]; then
  hdiutil detach "$DEV" >/dev/null 2>&1 || hdiutil detach "$DEV" -force >/dev/null 2>&1 || true
fi

echo "==> hdiutil convert (UDZO)"
hdiutil convert "$RW_DMG" -format UDZO -o "$DMG" -ov >/dev/null
rm -f "$RW_DMG"
rm -rf "$STAGE"

# 让挂载后的磁盘使用自定义卷图标
if [ -f "$APP/Contents/Resources/AppIcon.icns" ] && command -v SetFile >/dev/null 2>&1; then
  SetFile -a C "$DMG" || true
fi

echo "==> dmg ready: $DMG"
