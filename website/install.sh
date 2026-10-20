#!/bin/bash
# Installs or updates EasyShoot from the latest GitHub release.
#   curl -fsSL https://easyshoot.haythamasalama.me/install.sh | bash
# Downloading with curl skips the browser's quarantine flag, so macOS opens
# the app without the "can't be opened" prompt.
set -euo pipefail

URL="https://github.com/Haythamasalama/easyshoot/releases/latest/download/EasyShoot.zip"
APP="EasyShoot.app"

if [ "$(uname)" != "Darwin" ]; then
  echo "EasyShoot runs on macOS only." >&2
  exit 1
fi

DEST="/Applications"
if [ ! -w "$DEST" ]; then
  DEST="$HOME/Applications"
  mkdir -p "$DEST"
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "Downloading EasyShoot…"
curl -fL --progress-bar "$URL" -o "$TMP/EasyShoot.zip"
ditto -x -k "$TMP/EasyShoot.zip" "$TMP"

if [ ! -d "$TMP/$APP" ]; then
  echo "The download didn't contain $APP." >&2
  exit 1
fi

# Quit a running copy so it can be replaced.
osascript -e 'tell application id "com.haythamasalama.easyshoot" to quit' >/dev/null 2>&1 || true
pkill -x EasyShoot >/dev/null 2>&1 || true
sleep 1

rm -rf "$DEST/$APP"
mv "$TMP/$APP" "$DEST/$APP"
xattr -dr com.apple.quarantine "$DEST/$APP" 2>/dev/null || true

echo "Installed $DEST/$APP"
open "$DEST/$APP"
