#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
APP="$PWD/build/File Bucket.app"
mkdir -p "$APP/Contents/MacOS"
xcrun swiftc -O -target "$(uname -m)-apple-macosx13.0" Store.swift Settings.swift WindowSpring.swift DragMonitor.swift BucketPanel.swift DockController.swift StatusItem.swift main.swift -o "$APP/Contents/MacOS/FileBucket" -framework AppKit
/usr/libexec/PlistBuddy -c 'Print' Info.plist >/dev/null
cp Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"
printf 'Built %s\n' "$APP"
