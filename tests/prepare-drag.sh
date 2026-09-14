#!/bin/bash
# Quit the normal BuddyFiles first. Launch in the foreground in a separate terminal.
set -euo pipefail
cd "$(dirname "$0")/.."
if pgrep -x BuddyFiles >/dev/null; then
  echo 'Quit BuddyFiles before starting this isolated test.' >&2
  exit 1
fi
export BUCKET_HOME="$PWD/build/drag-state"
mkdir -p "$BUCKET_HOME"
./bucket clear
./bucket add "$PWD/fixtures/Hello bucket.txt" "$PWD/fixtures/second.txt"
rm -f "$BUCKET_HOME/drop-test.json"
export BUCKET_DROP_TEST=1
exec './build/BuddyFiles.app/Contents/MacOS/BuddyFiles' --app
