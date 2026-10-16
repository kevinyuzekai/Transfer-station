#!/usr/bin/env bash
# Build the SwiftPM executable and assemble a macOS .app bundle.
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$(pwd)"

APP_NAME="FileTransferStation"
DISPLAY_NAME="文件中转站"
BUNDLE_ID="com.kevin.transferstation"
VERSION="${VERSION:-1.1.0}"

DIST="$ROOT/dist"

echo "==> swift build -c release (universal: arm64 + x86_64)"
swift build -c release --arch arm64 --arch x86_64

BIN="$ROOT/.build/apple/Products/Release/$APP_NAME"
if [ ! -f "$BIN" ]; then BIN="$ROOT/.build/release/$APP_NAME"; fi
if [ ! -f "$BIN" ]; then
  BIN="$(find "$ROOT/.build" -type f -name "$APP_NAME" | head -n1)"
fi
if [ -z "$BIN" ] || [ ! -f "$BIN" ]; then
  echo "!! could not locate built binary" >&2
  exit 1
fi
echo "==> binary: $BIN ($(file "$BIN" 2>/dev/null || echo unknown))"

APP="$DIST/$APP_NAME.app"
rm -rf "$DIST"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/$APP_NAME"

# 应用图标：由 assets/AppIcon.png 生成 iconset 并编译为 .icns
ICON_SRC="$ROOT/assets/AppIcon.png"
if [ -f "$ICON_SRC" ]; then
  echo "==> iconutil: AppIcon.icns"
  ICONSET="$ROOT/.build/AppIcon.iconset"
  rm -rf "$ICONSET"
  mkdir -p "$ICONSET"
  make_icon() { sips -z "$1" "$1" "$ICON_SRC" --out "$ICONSET/$2" >/dev/null; }
  make_icon 16   "icon_16x16.png"
  make_icon 32   "icon_16x16@2x.png"
  make_icon 32   "icon_32x32.png"
  make_icon 64   "icon_32x32@2x.png"
  make_icon 128  "icon_128x128.png"
  make_icon 256  "icon_128x128@2x.png"
  make_icon 256  "icon_256x256.png"
  make_icon 512  "icon_256x256@2x.png"
  make_icon 512  "icon_512x512.png"
  make_icon 1024 "icon_512x512@2x.png"
  iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
else
  echo "!! assets/AppIcon.png not found; skipping app icon"
fi

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>$APP_NAME</string>
  <key>CFBundleDisplayName</key><string>$DISPLAY_NAME</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleExecutable</key><string>$APP_NAME</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSHumanReadableCopyright</key><string>Copyright 2026 Kevin</string>
</dict>
</plist>
PLIST

echo "==> ad-hoc codesign"
codesign --force --deep --sign - "$APP" || true

echo "==> app bundle ready: $APP"
