#!/bin/bash
# Builds AeroBar.app from the Swift Package.
#
# Usage: Scripts/build-app.sh [release|debug]
#
# Produces: .build/AeroBar.app
set -euo pipefail

CONFIG="${1:-release}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

echo "==> Building (swift build -c $CONFIG)"
swift build -c "$CONFIG"

BIN_PATH=".build/$CONFIG/AeroBar"
if [ ! -f "$BIN_PATH" ]; then
    echo "error: expected binary not found at $BIN_PATH" >&2
    exit 1
fi

APP_DIR=".build/AeroBar.app"
CONTENTS="$APP_DIR/Contents"
MACOS="$CONTENTS/MacOS"

echo "==> Assembling $APP_DIR"
rm -rf "$APP_DIR"
mkdir -p "$MACOS"
cp "$BIN_PATH" "$MACOS/AeroBar"
cp "Resources/Info.plist" "$CONTENTS/Info.plist"

echo "==> Ad-hoc code signing (required for SMAppService / Launch at Login)"
codesign --force --deep --sign - "$APP_DIR"

echo "==> Done: $APP_DIR"
