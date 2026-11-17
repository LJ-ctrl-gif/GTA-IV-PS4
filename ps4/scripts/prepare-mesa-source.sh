#!/usr/bin/env bash
# Prepare the pinned Mesa 26.0.8 source tree for the GTA IV PS4 RADV build.
# This fetches source code only; it does not fetch game data or build Mesa.
set -euo pipefail

HERE="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
source "$HERE/ps4-env.sh"

DOLPHINPS4_COMMIT="888ff3e913801c0c2b2531ddf4f767772ed45dd9"
MESA_TAG="mesa-26.0.8"
MESA_COMMIT="60e95b787857afbc9a00b693b91c0d9c8923a430"
DOLPHINPS4_REPO="${DOLPHINPS4_REPO:-$DOLPHIN_BUILD/DolphinPS4}"
MESA_SOURCE="${MESA_SOURCE:-$LR_ROOT/mesa-src}"
MESA_PATCH="$HERE/../patches/mesa-aco-mubuf-addr64.patch"

for tool in git cp mv mktemp; do
    command -v "$tool" >/dev/null 2>&1 || {
        echo "ERROR: required host command is missing: $tool" >&2
        exit 1
    }
done
[[ -f "$MESA_PATCH" ]] || { echo "ERROR: GTA IV Mesa patch not found: $MESA_PATCH" >&2; exit 1; }

# Refuse symlinked roots and pre-existing targets. Never overwrite a user's source tree.
[[ ! -L "$LR_ROOT" ]] || { echo "ERROR: LR_ROOT must not be a symlink: $LR_ROOT" >&2; exit 1; }
[[ ! -L "$DOLPHIN_BUILD" ]] || { echo "ERROR: DOLPHIN_BUILD must not be a symlink: $DOLPHIN_BUILD" >&2; exit 1; }
[[ ! -e "$DOLPHINPS4_REPO" ]] || { echo "ERROR: target already exists; refusing to replace: $DOLPHINPS4_REPO" >&2; exit 1; }
[[ ! -e "$MESA_SOURCE" ]] || { echo "ERROR: target already exists; refusing to replace: $MESA_SOURCE" >&2; exit 1; }

mkdir -p "$LR_ROOT" "$(dirname -- "$DOLPHINPS4_REPO")" "$(dirname -- "$MESA_SOURCE")"
STAGE="$(mktemp -d "$LR_ROOT/.mesa-source-prep.XXXXXX")"
cleanup() {
    case "${STAGE:-}" in
        "$LR_ROOT"/.mesa-source-prep.*)
            [[ ! -d "$STAGE" ]] || rm -rf -- "$STAGE"
            ;;
        *) echo "WARNING: refusing to remove unexpected staging path: $STAGE" >&2 ;;
    esac
}
trap cleanup EXIT

echo "Cloning pinned DolphinPS4 integration repository..."
git clone --quiet https://github.com/iHaiDeeZ/DolphinPS4.git "$STAGE/DolphinPS4"
git -C "$STAGE/DolphinPS4" checkout --quiet --detach "$DOLPHINPS4_COMMIT"
actual_commit="$(git -C "$STAGE/DolphinPS4" rev-parse HEAD)"
[[ "$actual_commit" == "$DOLPHINPS4_COMMIT" ]] || {
    echo "ERROR: DolphinPS4 revision mismatch: $actual_commit" >&2
    exit 1
}
[[ -f "$STAGE/DolphinPS4/patches/mesa-ps4.patch" ]] || {
    echo "ERROR: pinned DolphinPS4 checkout lacks patches/mesa-ps4.patch" >&2
    exit 1
}
[[ -f "$STAGE/DolphinPS4/port/mesa/ac_ps4_drm.c" ]] || {
    echo "ERROR: pinned DolphinPS4 checkout lacks port/mesa/ac_ps4_drm.c" >&2
    exit 1
}

echo "Cloning Mesa $MESA_TAG..."
git clone --quiet --depth 1 --branch "$MESA_TAG" https://gitlab.freedesktop.org/mesa/mesa.git "$STAGE/mesa-src"
mesa_version="$(tr -d '[:space:]' < "$STAGE/mesa-src/VERSION")"
[[ "$mesa_version" == "26.0.8" ]] || {
    echo "ERROR: expected Mesa 26.0.8, got $mesa_version" >&2
    exit 1
}
actual_mesa_commit="$(git -C "$STAGE/mesa-src" rev-parse HEAD)"
[[ "$actual_mesa_commit" == "$MESA_COMMIT" ]] || {
    echo "ERROR: Mesa 26.0.8 commit mismatch: $actual_mesa_commit" >&2
    exit 1
}

echo "Applying DolphinPS4's PS4 RADV integration..."
git -C "$STAGE/mesa-src" apply --check "$STAGE/DolphinPS4/patches/mesa-ps4.patch"
git -C "$STAGE/mesa-src" apply "$STAGE/DolphinPS4/patches/mesa-ps4.patch"
tr -d '\r' < "$STAGE/DolphinPS4/port/mesa/ac_ps4_drm.c" > "$STAGE/mesa-src/src/amd/common/ac_ps4_drm.c"

echo "Applying GTA IV's GFX7 MUBUF addr64 workaround..."
git -C "$STAGE/mesa-src" apply --check -p3 "$MESA_PATCH"
git -C "$STAGE/mesa-src" apply -p3 "$MESA_PATCH"

grep -Fq "is_ps4 = cc.get_define('__ORBIS__') != ''" "$STAGE/mesa-src/meson.build"
grep -Fq "mubuf_addr64_global" "$STAGE/mesa-src/src/amd/compiler/instruction_selection/aco_select_nir_intrinsics.cpp"
[[ -f "$STAGE/mesa-src/src/amd/common/ac_ps4_drm.c" ]]
grep -Fq "#ifdef __PS4__" "$STAGE/mesa-src/src/amd/vulkan/radv_cmd_buffer.c"

# Publish only after both patches and all required integration markers pass.
mv -- "$STAGE/DolphinPS4" "$DOLPHINPS4_REPO"
mv -- "$STAGE/mesa-src" "$MESA_SOURCE"

echo "Mesa PS4 source prepared successfully."
echo "  DolphinPS4: $DOLPHINPS4_REPO ($DOLPHINPS4_COMMIT)"
echo "  Mesa:       $MESA_SOURCE (26.0.8 $MESA_COMMIT + PS4 integration + GTA IV ACO patch)"
echo "Next: build the DolphinPS4 sysroot and Mesa static libraries using its pinned scripts."
