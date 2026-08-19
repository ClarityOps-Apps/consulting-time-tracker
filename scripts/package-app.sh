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
  Time/WorkTypeEditor.swift

sed 's/\$(PRODUCT_BUNDLE_IDENTIFIER)/co.clarityops.Time/' "$ROOT/Time/Info.plist" > "$APP/Contents/Info.plist"

echo "Built $APP"
