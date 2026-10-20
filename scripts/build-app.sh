#!/usr/bin/env bash
# Builds EasyShoot.app into ./build
#   ./scripts/build-app.sh               native architecture, release
#   UNIVERSAL=1 ./scripts/build-app.sh   arm64 + x86_64
#   SIGN_IDENTITY="Developer ID Application: ..." ./scripts/build-app.sh
set -euo pipefail
cd "$(dirname "$0")/.."

ARCH_FLAGS=()
if [[ "${UNIVERSAL:-0}" == "1" ]]; then
  ARCH_FLAGS=(--arch arm64 --arch x86_64)
fi

swift build -c release ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"}
BIN_DIR=$(swift build -c release ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"} --show-bin-path)

APP=build/EasyShoot.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/EasyShoot" "$APP/Contents/MacOS/EasyShoot"
cp Resources/Info.plist "$APP/Contents/Info.plist"
if [[ -d Resources/AppIcon.iconset ]]; then
  iconutil -c icns Resources/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"
fi

codesign --force --deep --sign "${SIGN_IDENTITY:--}" "$APP"
echo "Built $APP"
