#!/bin/bash
# Package the independent GTA IV Setup Manager PS4 application.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
source "$HERE/ps4-env.sh"
VERSION="$1"
if [[ ! "$VERSION" =~ ^[0-9]{2}\.[0-9]{2}$ ]]; then
    echo "usage: package-setup-manager.sh <version XX.YY>" >&2
    exit 1
fi
BUILD_DIR="$LR_SRC/out/build/ps4-release/GTAIVSetupManager"
EBOOT="$BUILD_DIR/eboot.bin"
[ -s "$EBOOT" ] || { echo "missing $EBOOT: build GTAIVSetupManager first" >&2; exit 1; }
mkdir -p "$LR_ROOT/build"
STAGE="$(mktemp -d "$LR_ROOT/build/setup-manager-stage.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT
mkdir -p "$STAGE/sce_sys"
cp "$EBOOT" "$STAGE/eboot.bin"
python3 "$LR_SRC/ps4/setup-manager/generate-icon.py" "$STAGE/sce_sys/icon0.png"
PKG="$("$HERE/make-pkg.sh" "$STAGE" GIVS00001 "GTA IV Setup Manager" "$VERSION" GTAIVSETUPMGR "$LR_ROOT/out" | tail -1)"
test -s "$PKG"
ls -lh "$PKG"
