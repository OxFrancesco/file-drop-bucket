#!/bin/bash
# Build separately. Never replace the signed release or modify macOS permissions.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
work="${1:?Usage: ./build.sh /absolute/path/to/new-source-directory}"
if [[ -e "$work" ]]; then
  echo 'Choose a new source directory; refusing to overwrite an existing checkout.' >&2
  exit 1
fi
git -c filter.lfs.process= -c filter.lfs.smudge= -c filter.lfs.required=false clone \
  --branch v0.3.3 --depth 1 https://github.com/iFurySt/open-codex-computer-use.git "$work"
cd "$work"
test "$(git rev-parse HEAD)" = 41c5294cfe4735baca03f9c82b4de99d191a0b49
git apply --check "$here/ocu-0.3.3-native-drag.patch"
git apply "$here/ocu-0.3.3-native-drag.patch"
swift test
OPEN_COMPUTER_USE_CODESIGN_MODE=adhoc ./scripts/build-open-computer-use-app.sh debug
printf '\nBuilt: %s/dist/Open Computer Use (Dev).app\n' "$work"
printf 'Grant this separate app Accessibility and Screen Recording manually before testing.\n'
