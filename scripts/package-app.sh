#!/bin/sh
# Assemble Time.app with the Swift compiler (Command Line Tools).
# Prefer opening Time.xcodeproj in Xcode when it is installed.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SDK="$(xcrun --show-sdk-path)"
ARCH="$(uname -m)"
TARGET="${ARCH}-apple-macos14.0"
APP="$ROOT/Time.app"
ICONSET_SRC="$ROOT/Time/Assets.xcassets/AppIcon.appiconset"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

swiftc \
  -swift-version 5 \
  -sdk "$SDK" \
  -target "$TARGET" \
  -O \
  -framework SwiftUI \
  -framework AppKit \
  -framework Combine \
  -lsqlite3 \
  -o "$APP/Contents/MacOS/Time" \
  Time/main.swift \
  Time/AppDelegate.swift \
  Time/Theme.swift \
  Time/Models.swift \
  Time/Database.swift \
  Time/TimeStore.swift \
  Time/TimeWindowView.swift \
  Time/HistoryView.swift \
  Time/ReportView.swift \
  Time/WorkTypeEditor.swift \
  Time/ColorsView.swift

# Build AppIcon.icns from the signed-off AppIcon.appiconset (Applications / Dock / About).
# Menu bar glyph stays the separate template drawn in statusClockImage() — not this tile.
TMP_ICONSET="$ROOT/.build-AppIcon.iconset"
rm -rf "$TMP_ICONSET"
mkdir -p "$TMP_ICONSET"
for f in \
  icon_16x16.png diana.k@example.org \
  icon_32x32.png ivan.p@example.net \
  icon_128x128.png wendy.h@example.net \
  icon_256x256.png wendy.h@example.net \
  icon_512x512.png walt.e@example.net
do
  cp "$ICONSET_SRC/$f" "$TMP_ICONSET/$f"
done
iconutil -c icns "$TMP_ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$TMP_ICONSET"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>en</string>
	<key>CFBundleDisplayName</key>
	<string>Time</string>
	<key>CFBundleExecutable</key>
	<string>Time</string>
	<key>CFBundleIconFile</key>
	<string>AppIcon</string>
	<key>CFBundleIconName</key>
	<string>AppIcon</string>
	<key>CFBundleIdentifier</key>
	<string>co.clarityops.Time</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>Time</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>1.0</string>
	<key>CFBundleVersion</key>
	<string>1</string>
	<key>LSMinimumSystemVersion</key>
	<string>14.0</string>
	<key>NSHighResolutionCapable</key>
	<true/>
	<key>NSPrincipalClass</key>
	<string>NSApplication</string>
</dict>
</plist>
PLIST

echo -n 'APPL????' > "$APP/Contents/PkgInfo"
codesign --force --sign - "$APP" >/dev/null 2>&1 || true
echo "Built $APP"
