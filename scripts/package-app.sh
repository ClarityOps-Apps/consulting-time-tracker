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
  Time/ClientEditor.swift \
  Time/ProjectEditor.swift \
  Time/ColorsView.swift

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
