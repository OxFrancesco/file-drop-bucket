#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
EXTENSIONS="${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}/extensions"
CLI="$ROOT/build/File Bucket.app/Contents/MacOS/FileBucket"
TARGET="$HOME/.local/bin/file-bucket"
[[ -x "$CLI" ]] || { printf 'Build the app with ./build.sh first.\n' >&2; exit 1; }
mkdir -p "$EXTENSIONS" "$(dirname "$TARGET")"
if [[ -e "$TARGET" || -L "$TARGET" ]]; then
  [[ -L "$TARGET" && "$(readlink "$TARGET")" == "$CLI" ]] || {
    printf 'Refusing to replace existing CLI: %s\n' "$TARGET" >&2; exit 1;
  }
else
  ln -s "$CLI" "$TARGET"
fi
# Copy avoids symlink module-resolution surprises. Re-run after source changes.
DEST="$EXTENSIONS/file-bucket.ts"
if [[ -e "$DEST" || -L "$DEST" ]]; then
  cmp -s "$ROOT/integrations/file-bucket.ts" "$DEST" || {
    printf 'Refusing to overwrite different extension: %s. Back it up and remove it before reinstalling.\n' "$DEST" >&2; exit 1;
  }
else
  cp "$ROOT/integrations/file-bucket.ts" "$DEST"
fi
printf 'Installed %s\nCLI link: %s\nRun /reload in Pi, or restart Pi.\n' "$DEST" "$TARGET"
