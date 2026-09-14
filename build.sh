#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
APP="$PWD/build/BuddyFiles.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" build/BuddyFiles.iconset
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" assets/BuddyFiles.png --out "build/BuddyFiles.iconset/icon_${size}x${size}.png" >/dev/null
  doubled=$((size * 2))
  sips -z "$doubled" "$doubled" assets/BuddyFiles.png --out "build/BuddyFiles.iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns build/BuddyFiles.iconset -o "$APP/Contents/Resources/BuddyFiles.icns"
xcrun swiftc -O -target "$(uname -m)-apple-macosx13.0" Store.swift Settings.swift WindowSpring.swift DragMonitor.swift BucketPanel.swift DockController.swift StatusItem.swift main.swift -o "$APP/Contents/MacOS/BuddyFiles" -framework AppKit
/usr/libexec/PlistBuddy -c 'Print' Info.plist >/dev/null
cp Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"
printf 'Built %s\n' "$APP"
