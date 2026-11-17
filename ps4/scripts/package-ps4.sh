#!/bin/bash
# Package the PS4 build (after build-ps4.sh) as a fake PKG, LBTY00001.
#
#   package-ps4.sh <version XX.YY>
#
# Bump the version for every package installed on the console.
#
# The PKG holds the program and its read-only resources only:
#   /app0/eboot.bin
#   /app0/sce_sys/            param.sfo, icon0.png, pic1.png, about/right.sprx
#   /app0/sce_module/         OpenOrbis libc.prx / libSceFios2.prx
#   /app0/Resources/          aes_key.bin, button_prompts/, font_atlases/
# The game itself is installed on the console: copy the disc and title update
# to /data/LibertyRecomp/source/ (see the README) and start the app.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/ps4-env.sh"

VERSION="${1:?usage: package-ps4.sh <version XX.YY>}"
[[ "$VERSION" =~ ^[0-9]{2}\.[0-9]{2}$ ]] || { echo "version must look like 01.00" >&2; exit 1; }
BUILD_DIR="$LR_SRC/out/build/ps4-release"
EBOOT="$BUILD_DIR/LibertyRecomp/eboot.bin"
OELF="$BUILD_DIR/LibertyRecomp/LibertyRecomp.oelf"
LIB="$LR_SRC/LibertyRecompLib"
[ -f "$EBOOT" ] || { echo "missing $EBOOT: run build-ps4.sh first" >&2; exit 1; }
[ -f "$OELF" ] || { echo "missing $OELF: refusing to package without the validated OELF" >&2; exit 1; }
[[ ! -L "$LR_ROOT" ]] || { echo "LR_ROOT must not be a symlink: $LR_ROOT" >&2; exit 1; }
[[ ! -L "$LR_ROOT/build" ]] || { echo "build directory must not be a symlink: $LR_ROOT/build" >&2; exit 1; }
mkdir -p "$LR_ROOT/build"
STAGE="$(mktemp -d "$LR_ROOT/build/pkg-stage.XXXXXX")"
cleanup_stage() {
    case "${STAGE:-}" in
        "$LR_ROOT"/build/pkg-stage.*)
            [[ ! -d "$STAGE" ]] || rm -rf -- "$STAGE"
            ;;
        *) echo "WARNING: refusing to remove unexpected package stage: $STAGE" >&2 ;;
    esac
}
trap cleanup_stage EXIT
mkdir -p "$STAGE/sce_sys" "$STAGE/Resources"

cp "$EBOOT" "$STAGE/eboot.bin"
cp "$LR_SRC/LibertyRecomp/res/ps4/sce_sys/icon0.png" "$LR_SRC/LibertyRecomp/res/ps4/sce_sys/pic1.png" \
    "$STAGE/sce_sys/"

cp "$LIB/aes_key.bin" "$STAGE/Resources/"
mkdir -p "$STAGE/Resources/button_prompts"
for variant_dir in "$LIB/private/button_prompts"/*/; do
    variant="$(basename "$variant_dir")"
    if [ -f "$variant_dir/buttons_360.xtd" ]; then
        mkdir -p "$STAGE/Resources/button_prompts/$variant"
        cp "$variant_dir/buttons_360.xtd" "$STAGE/Resources/button_prompts/$variant/"
    fi
done
# The runtime font atlases only, as the macOS bundle ships them (the source tree also holds
# review/tool folders, and PkgTool's pkg_build crashes on some nested folders).
for set_dir in "" tlad tbogt; do
    mkdir -p "$STAGE/Resources/font_atlases/$set_dir"
    cp "$LIB/font_atlases/$set_dir"/font{1,2,3}.png "$LIB/font_atlases/$set_dir/manifest.json" \
        "$STAGE/Resources/font_atlases/$set_dir/"
done

PKG="$("$HERE/make-pkg.sh" "$STAGE" LBTY00001 "Liberty Recompiled" "$VERSION" LIBERTYRECOMP "$LR_ROOT/out" | tail -1)"

# Keep the symbols of every packaged build for symbolizing console crash logs.
mkdir -p "$LR_ROOT/oelf"
cp "$OELF" "$LR_ROOT/oelf/v$VERSION.oelf"

ls -la "$PKG"
