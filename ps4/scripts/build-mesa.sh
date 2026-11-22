#!/usr/bin/env bash
# Build the pinned DolphinPS4 RADV static libraries using its upstream Mesa build script.
# Usage: build-mesa.sh [setup] [ninja targets...]
set -euo pipefail

HERE="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
source "$HERE/ps4-env.sh"

DOLPHINPS4_REPO="${DOLPHINPS4_REPO:-$DOLPHIN_BUILD/DolphinPS4}"
MESA_SOURCE="${MESA_SOURCE:-$LR_ROOT/mesa-src}"
MESA_COMMIT="60e95b787857afbc9a00b693b91c0d9c8923a430"
DOLPHINPS4_COMMIT="888ff3e913801c0c2b2531ddf4f767772ed45dd9"
MESA_LINK="$DOLPHIN_BUILD/src/mesa"
MESA_BUILD="$DOLPHIN_BUILD/build/mesa"
MESA_BUILD_LINK="$LR_ROOT/mesa-build"

export PATH="$DOLPHIN_BUILD/mesa-venv/bin:$LR_ROOT/host-tools/bin:$PATH"

[[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]] || {
    echo "ERROR: Mesa PS4 build requires Linux x86_64." >&2
    exit 1
}
for tool in git readlink ln meson ninja pkg-config; do
    command -v "$tool" >/dev/null 2>&1 || {
        echo "ERROR: required host command is missing: $tool" >&2
        exit 1
    }
done
[[ -f "$DOLPHINPS4_REPO/scripts/build-mesa.sh" ]] || {
    echo "ERROR: DolphinPS4 build-mesa.sh missing; run prepare-mesa-source.sh first." >&2
    exit 1
}
[[ "$(git -C "$DOLPHINPS4_REPO" rev-parse HEAD)" == "$DOLPHINPS4_COMMIT" ]] || {
    echo "ERROR: DolphinPS4 checkout is not the pinned revision $DOLPHINPS4_COMMIT." >&2
    exit 1
}
[[ -d "$MESA_SOURCE" && -f "$MESA_SOURCE/VERSION" ]] || {
    echo "ERROR: prepared Mesa source missing; run prepare-mesa-source.sh first." >&2
    exit 1
}
[[ "$(tr -d '[:space:]' < "$MESA_SOURCE/VERSION")" == "26.0.8" ]] || {
    echo "ERROR: expected Mesa 26.0.8 source." >&2
    exit 1
}
[[ "$(git -C "$MESA_SOURCE" rev-parse HEAD)" == "$MESA_COMMIT" ]] || {
    echo "ERROR: Mesa source commit does not match the dependency lock." >&2
    exit 1
}
[[ -x "$DOLPHIN_BUILD/mesa-venv/bin/meson" ]] || {
    echo "ERROR: install Meson in $DOLPHIN_BUILD/mesa-venv (see ps4/DEPENDENCIES.md)." >&2
    exit 1
}
[[ -d "$DOLPHIN_BUILD/src/libdrm/include/drm" ]] || {
    echo "ERROR: DolphinPS4 libdrm headers are missing under $DOLPHIN_BUILD/src/libdrm." >&2
    exit 1
}
[[ -d "$DOLPHIN_SYSROOT/libc-overlay" && -f "$DOLPHIN_SYSROOT/lib/libc++.a" ]] || {
    echo "ERROR: DolphinPS4 PS4 sysroot is incomplete." >&2
    exit 1
}
[[ ! -L "$LR_ROOT" && ! -L "$DOLPHIN_BUILD" ]] || {
    echo "ERROR: build roots must not be symlinks." >&2
    exit 1
}
[[ ! -L "$DOLPHIN_BUILD/src" && ! -L "$DOLPHIN_BUILD/build" ]] || {
    echo "ERROR: DolphinPS4 src/build directories must not be symlinks." >&2
    exit 1
}

mkdir -p "$DOLPHIN_BUILD/src" "$DOLPHIN_BUILD/build" "$LR_ROOT"
if [[ -e "$MESA_LINK" || -L "$MESA_LINK" ]]; then
    [[ -L "$MESA_LINK" && "$(readlink -f "$MESA_LINK")" == "$(readlink -f "$MESA_SOURCE")" ]] || {
        echo "ERROR: refusing to replace existing Mesa source path: $MESA_LINK" >&2
        exit 1
    }
else
    ln -s "$MESA_SOURCE" "$MESA_LINK"
fi

if [[ -e "$MESA_BUILD_LINK" || -L "$MESA_BUILD_LINK" ]]; then
    [[ -L "$MESA_BUILD_LINK" && "$(readlink -f "$MESA_BUILD_LINK")" == "$(readlink -m "$MESA_BUILD")" ]] || {
        echo "ERROR: refusing to replace existing Mesa build path: $MESA_BUILD_LINK" >&2
        exit 1
    }
else
    ln -s "$MESA_BUILD" "$MESA_BUILD_LINK"
fi

# The upstream script uses DOLPHIN_BUILD for sysroot/libdrm and its own build directory.
# Add the GTA IV host shader tools after its venv and host-tools paths.
export PATH="$LR_ROOT/host-tools/bin:$PATH"
export PS4_BUILD_ROOT="$DOLPHIN_BUILD"
export PS4_SYSROOT="$DOLPHIN_SYSROOT"
export DOLPHIN_BUILD
export DOLPHIN_SYSROOT
export OPENORBIS

echo "Building Mesa RADV from $MESA_COMMIT..."
bash "$DOLPHINPS4_REPO/scripts/build-mesa.sh" "$@"

[[ -d "$MESA_BUILD" ]] || { echo "ERROR: upstream Mesa build did not create $MESA_BUILD" >&2; exit 1; }
echo "Mesa RADV build completed: $MESA_BUILD"
echo "GTA IV PS4 build will consume: $MESA_BUILD_LINK"
