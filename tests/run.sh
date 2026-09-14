#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
./build.sh
codesign --verify --deep --strict 'build/BuddyFiles.app'
python3 tests/check-cli.py
bun tests/check-receiver.js
xcrun swiftc -parse-as-library PasteboardTest.swift -o build/pasteboard-test -framework AppKit
build/pasteboard-test "$PWD/fixtures/Hello bucket.txt"
printf '%s\n' 'CLI and pasteboard checks passed. This does NOT prove native dragging.'
