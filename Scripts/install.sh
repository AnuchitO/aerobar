#!/bin/bash
# Builds Workspaces.app and installs it into /Applications.
#
# Usage: Scripts/install.sh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

Scripts/build-app.sh release

DEST="/Applications/Workspaces.app"

echo "==> Installing to $DEST"
if [ -d "$DEST" ]; then
    echo "    (removing previous install)"
    rm -rf "$DEST"
fi
cp -R ".build/Workspaces.app" "$DEST"

echo "==> Installed."
echo "    Launch it with:  open $DEST"
echo "    Or from Finder:  /Applications/Workspaces.app"
