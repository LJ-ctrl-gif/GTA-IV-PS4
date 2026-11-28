#!/bin/bash
# Builds the overlay toolchain ($OO_PS4_TOOLCHAIN) and fake LLVM prefix used by the PS4 build,
# and stages the extracted game files. Existing toolchain directories are preserved as backups.
set -euo pipefail

PREFLIGHT_ONLY=false
if [[ "${1:-}" == "--preflight-only" ]]; then
    PREFLIGHT_ONLY=true
elif [[ "$#" -gt 0 ]]; then
    echo "ERROR: unknown argument: $1" >&2
    exit 2
fi

# The pinned Microsoft DXC release used below only provides a Linux x86_64 asset.
# Reject unsupported hosts before sourcing the environment or touching build paths.
HOST_OS="$(uname -s)"
HOST_ARCH="$(uname -m)"
if [[ "$HOST_OS" != "Linux" || "$HOST_ARCH" != "x86_64" ]]; then
    echo "ERROR: PS4 toolchain setup requires x86_64 Linux (detected: $HOST_OS/$HOST_ARCH)." >&2
    echo "Aborting before modifying build files." >&2
    exit 1
fi

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd -P)"
HOME_INPUT="${HOME:?HOME must be set}"
if [[ ! -d "$HOME_INPUT" ]]; then
    echo "ERROR: HOME must already exist and be a directory: $HOME_INPUT" >&2
    exit 1
fi
HOME_REAL="$(cd -- "$HOME_INPUT" && pwd -P)"
LR_ROOT_INPUT="${LR_ROOT:-$HOME_REAL/libertyrecomp-ps4-build}"

# Resolve the parent without creating LR_ROOT. Requiring an existing parent and a plain
# final path component keeps canonicalization side-effect-free and prevents symlink roots.
if [[ "$LR_ROOT_INPUT" != /* ]]; then
    echo "ERROR: LR_ROOT must be an absolute path: $LR_ROOT_INPUT" >&2
    exit 1
fi
if [[ "$LR_ROOT_INPUT" == "/" || "$LR_ROOT_INPUT" == */ ]]; then
    echo "ERROR: LR_ROOT must name a dedicated directory, not a filesystem root: $LR_ROOT_INPUT" >&2
    exit 1
fi
LR_PARENT_INPUT="$(dirname -- "$LR_ROOT_INPUT")"
LR_BASE="$(basename -- "$LR_ROOT_INPUT")"
if [[ -z "$LR_BASE" || "$LR_BASE" == "." || "$LR_BASE" == ".." ]]; then
    echo "ERROR: invalid LR_ROOT directory name: $LR_ROOT_INPUT" >&2
    exit 1
fi
if [[ ! -d "$LR_PARENT_INPUT" ]]; then
    echo "ERROR: LR_ROOT parent must already exist: $LR_PARENT_INPUT" >&2
    exit 1
fi
# Check the caller-supplied final component before canonicalizing its parent;
# resolving the parent first would otherwise hide a symlink at LR_ROOT itself.
if [[ -L "$LR_ROOT_INPUT" ]]; then
    echo "ERROR: LR_ROOT must not be a symbolic link: $LR_ROOT_INPUT" >&2
    exit 1
fi
LR_PARENT="$(cd -- "$LR_PARENT_INPUT" && pwd -P)"
LR_ROOT="$LR_PARENT/$LR_BASE"

if [[ -L "$LR_ROOT" ]]; then
    echo "ERROR: LR_ROOT must not be a symbolic link: $LR_ROOT" >&2
    exit 1
fi
if [[ -e "$LR_ROOT" && ! -d "$LR_ROOT" ]]; then
    echo "ERROR: LR_ROOT exists but is not a directory: $LR_ROOT" >&2
    exit 1
fi
if [[ "$LR_ROOT" == "$HOME_REAL" ]]; then
    echo "ERROR: LR_ROOT must be a dedicated directory below HOME, not HOME itself." >&2
    exit 1
fi
case "$LR_ROOT/" in
    "$HOME_REAL/"*) ;;
    *)
        echo "ERROR: LR_ROOT must be located below HOME: $LR_ROOT" >&2
        exit 1
        ;;
esac
case "$LR_ROOT/" in
    "$REPO_ROOT/"*)
        echo "ERROR: LR_ROOT must not be inside the GTA IV repository: $LR_ROOT" >&2
        exit 1
        ;;
esac

# The documented layout is $LR_ROOT/src/LibertyRecomp, so the repository is allowed
# to be nested below LR_ROOT. Only reject LR_ROOT inside the repository itself.
# Check every managed directory before the first mkdir, source, download or build write.
MANAGED_DIRS=(
    "$LR_ROOT/oo"
    "$LR_ROOT/llvm"
    "$LR_ROOT/build"
    "$LR_ROOT/build/host-shader-tools"
    "$LR_ROOT/host-tools"
    "$LR_ROOT/host-tools/bin"
    "$LR_ROOT/host-tools/dxc"
    "$LR_ROOT/host-tools/dxc/bin"
    "$LR_ROOT/host-tools/dxc/lib"
    "$LR_ROOT/host-compat"
    "$LR_ROOT/game"
    "$LR_ROOT/game/iso"
    "$LR_ROOT/game/payload"
    "$LR_ROOT/game/SystemUpdate"
)
for target in "${MANAGED_DIRS[@]}"; do
    if [[ -L "$target" ]]; then
        echo "ERROR: refusing symlinked managed path: $target" >&2
        exit 1
    fi
    if [[ -e "$target" && ! -d "$target" ]]; then
        echo "ERROR: managed path exists but is not a directory: $target" >&2
        exit 1
    fi
done

# All path checks have passed. Creating LR_ROOT is now safe.
if [[ ! -d "$LR_ROOT" ]]; then
    mkdir -- "$LR_ROOT"
fi
if [[ "$PREFLIGHT_ONLY" == true ]]; then
    echo "PS4 toolchain path preflight passed: $LR_ROOT"
    exit 0
fi

export LR_ROOT
HOST_PATH="$PATH"
source "$SCRIPT_DIR/ps4-env.sh"

# Fail before creating staging directories or downloading DXC when upstream inputs are absent.
missing=0
for tool in cmake ninja curl tar sha256sum clang-21 clang++-21 ld.lld-21 lld-21 llvm-ar-21 llvm-ranlib-21 llvm-nm-21 llvm-objcopy-21 llvm-strip-21; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "ERROR: required host tool is missing: $tool" >&2
        missing=1
    fi
done
for path in \
    "$OPENORBIS/bin/ld.lld" \
    "$OPENORBIS/bin/create-fself" \
    "$OPENORBIS/link.x" \
    "$OPENORBIS/lib/crt1.o" \
    "$OPENORBIS/lib/libclang_rt.builtins-x86_64.a" \
    "$DOLPHIN_SYSROOT/include/c++/v1/__config_site" \
    "$DOLPHIN_SYSROOT/lib/libc++.a" \
    "$DOLPHIN_SYSROOT/lib/libc++abi.a" \
    "$DOLPHIN_SYSROOT/libc-overlay" \
    "$DOLPHIN_BUILD/src/dolphin/Externals/glslang/glslang" \
    "$LR_SRC/tools/OpenOrbis-PS4-Toolchain/scripts" \
    "$LR_SRC/glue/rexglue-sdk-main/thirdparty" \
    "$LR_SCRIPTS/host-shader-tools"; do
    if [[ ! -e "$path" ]]; then
        echo "ERROR: required PS4 build input is missing: $path" >&2
        missing=1
    fi
done
if [[ "$missing" -ne 0 ]]; then
    echo "Aborting before toolchain staging or downloads. See ps4/DEPENDENCIES.md." >&2
    exit 1
fi

REPO_OO="$LR_SRC/tools/OpenOrbis-PS4-Toolchain"
STAGE_ROOT="$(mktemp -d "$LR_ROOT/.toolchain-stage.XXXXXX")"
cleanup_stage() {
    if [[ -n "${STAGE_ROOT:-}" && -d "$STAGE_ROOT" ]]; then
        case "$STAGE_ROOT" in
            "$LR_ROOT"/.toolchain-stage.*) rm -rf -- "$STAGE_ROOT" ;;
            *) echo "WARNING: refusing to remove unexpected staging path: $STAGE_ROOT" >&2 ;;
        esac
    fi
}
trap cleanup_stage EXIT

OO="$STAGE_ROOT/oo"
LLVM="$STAGE_ROOT/llvm"
mkdir -p "$OO/lib" "$OO/include" "$OO/bin" "$LLVM/bin" "$LLVM/include"

# --- Overlay toolchain: PacBrew OpenOrbis + repo scripts + DolphinPS4 libc++ ---
for f in "$OPENORBIS"/*; do
    [[ -e "$f" ]] || continue
    case "$(basename "$f")" in lib|include|bin) ;; *) ln -s "$f" "$OO/" ;; esac
done
for f in "$OPENORBIS"/lib/*; do
    [[ -e "$f" ]] || continue
    ln -s "$f" "$OO/lib/"
done
for f in "$OPENORBIS"/bin/*; do
    [[ -e "$f" ]] || continue
    ln -s "$f" "$OO/bin/"
done
for f in "$OPENORBIS"/include/*; do
    [[ -e "$f" ]] || continue
    [ "$(basename "$f")" = "c++" ] || ln -s "$f" "$OO/include/"
done
# PS4 __config_site overlay dir the toolchain puts first on the C++ include path.
mkdir -p "$OO/include/c++/v1"
cp "$DOLPHIN_SYSROOT/include/c++/v1/__config_site" "$OO/include/c++/v1/__config_site"
# Python helpers referenced by LibertyRecomp's CMake (make_fself.py etc.) live in the repo copy.
ln -s "$REPO_OO/scripts" "$OO/scripts"
# libcxx_ps4_compat.a = LLVM 21 libc++ + libc++abi compiled for PS4 (from DolphinPS4).
mkdir -p "$STAGE_ROOT/ar-work"
(
    cd "$STAGE_ROOT/ar-work"
    printf 'CREATE %s\nADDLIB %s\nADDLIB %s\nSAVE\nEND\n' \
        "$OO/lib/libcxx_ps4_compat.a" "$DOLPHIN_SYSROOT/lib/libc++.a" "$DOLPHIN_SYSROOT/lib/libc++abi.a" \
        | llvm-ar-21 -M
)

# --- Fake LLVM prefix: host clang 21 + DolphinPS4 libc++ headers ---
for t in clang clang++ ld.lld lld llvm-ar llvm-ranlib llvm-nm llvm-objcopy llvm-strip; do
    real="$(PATH="$HOST_PATH" command -v "$t-21" || PATH="$HOST_PATH" command -v "$t")"
    ln -s "$real" "$LLVM/bin/$t"
done
ln -s "$DOLPHIN_SYSROOT/include/c++" "$LLVM/include/c++"

# --- Host shader tools: spirv-val + glslangValidator (with optimizer) from the SDK's submodules ---
HST_BUILD="$LR_ROOT/build/host-shader-tools"
mkdir -p "$LR_ROOT/host-tools/bin"
if [ ! -x "$LR_ROOT/host-tools/bin/spirv-val" ] || [ ! -x "$LR_ROOT/host-tools/bin/glslangValidator" ]; then
    cmake -S "$LR_SCRIPTS/host-shader-tools" -B "$HST_BUILD" -G Ninja -DCMAKE_BUILD_TYPE=Release \
        -DREXGLUE_THIRDPARTY="$LR_SRC/glue/rexglue-sdk-main/thirdparty" \
        -DGLSLANG_SOURCE_DIR="$DOLPHIN_BUILD/src/dolphin/Externals/glslang/glslang" \
        -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
        -DCMAKE_C_COMPILER=clang-21 -DCMAKE_CXX_COMPILER=clang++-21 >/dev/null
    cmake --build "$HST_BUILD" --target spirv-val glslang-standalone
    cp "$HST_BUILD/spirv-tools/tools/spirv-val" "$LR_ROOT/host-tools/bin/"
    cp "$HST_BUILD/glslang/StandAlone/glslang" "$LR_ROOT/host-tools/bin/glslangValidator"
fi

# --- DXC for the HLSL shader overrides: the bundled DXC 1.8 library crashes in SPIRV-Tools on the
# Bink pixel shaders (the macOS build has the same workaround), so the bundled dxc front end runs
# against a current libdxcompiler from Microsoft's official release. ---
DXC_VERSION="v1.9.2609"
DXC_ASSET="linux_dxc_2026_09_28.x86_x64.tar.gz"
if [ ! -f "$LR_ROOT/host-tools/dxc/lib/libdxcompiler.so" ]; then
    mkdir -p "$LR_ROOT/host-tools/dxc"
    curl -sSLf -o "$LR_ROOT/host-tools/dxc/dxc.tar.gz" \
        "https://github.com/microsoft/DirectXShaderCompiler/releases/download/$DXC_VERSION/$DXC_ASSET"
    DXC_SHA256="96faadc7f5c282d2ffda49804beb4c3ee38127bc252b723234e3c5cdf7aa39a1"
    printf '%s  %s\n' "$DXC_SHA256" "$LR_ROOT/host-tools/dxc/dxc.tar.gz" | sha256sum --check --status || {
        echo "ERROR: DXC archive SHA-256 verification failed; refusing extraction." >&2
        rm -f -- "$LR_ROOT/host-tools/dxc/dxc.tar.gz"
        exit 1
    }
    tar xzf "$LR_ROOT/host-tools/dxc/dxc.tar.gz" -C "$LR_ROOT/host-tools/dxc"
    rm "$LR_ROOT/host-tools/dxc/dxc.tar.gz"
fi

# --- Game payload: extracted ISO minus the console system-update folder ---
if [ -d "$LR_ROOT/game/iso" ] && [ ! -d "$LR_PAYLOAD" ]; then
    mv "$LR_ROOT/game/iso" "$LR_PAYLOAD"
fi
if [ -d "$LR_PAYLOAD/\$SystemUpdate" ]; then
    mv "$LR_PAYLOAD/\$SystemUpdate" "$LR_ROOT/game/SystemUpdate"
fi

# Install the completed toolchain atomically. Previous directories are retained as timestamped
# backups rather than recursively deleted, so a failed rebuild cannot destroy the last working copy.
BACKUP_SUFFIX="$(date -u +%Y%m%dT%H%M%SZ)-$$"
OO_BACKUP="$LR_ROOT/oo.backup.$BACKUP_SUFFIX"
LLVM_BACKUP="$LR_ROOT/llvm.backup.$BACKUP_SUFFIX"
backup_existing() {
    local target="$1"
    local backup="$2"
    if [[ -e "$target" ]]; then
        if [[ -L "$target" || ! -d "$target" ]]; then
            echo "ERROR: refusing to move unexpected toolchain target: $target" >&2
            return 1
        fi
        if [[ -e "$backup" || -L "$backup" ]]; then
            echo "ERROR: backup path already exists: $backup" >&2
            return 1
        fi
        mv -- "$target" "$backup"
    fi
}
restore_backups() {
    if [[ -n "$OO_BACKUP" && -d "$OO_BACKUP" && ! -e "$LR_ROOT/oo" ]]; then
        mv -- "$OO_BACKUP" "$LR_ROOT/oo"
    fi
    if [[ -n "$LLVM_BACKUP" && -d "$LLVM_BACKUP" && ! -e "$LR_ROOT/llvm" ]]; then
        mv -- "$LLVM_BACKUP" "$LR_ROOT/llvm"
    fi
}

if ! backup_existing "$LR_ROOT/oo" "$OO_BACKUP"; then
    restore_backups
    exit 1
fi
if ! backup_existing "$LR_ROOT/llvm" "$LLVM_BACKUP"; then
    restore_backups
    exit 1
fi
if ! mv -- "$OO" "$LR_ROOT/oo"; then
    restore_backups
    exit 1
fi
if ! mv -- "$LLVM" "$LR_ROOT/llvm"; then
    mv -- "$LR_ROOT/oo" "$OO" || true
    restore_backups
    exit 1
fi

echo "OO_PS4_TOOLCHAIN=$LR_ROOT/oo"
ls -la "$LR_ROOT/oo/lib/libcxx_ps4_compat.a"
"$LR_ROOT/llvm/bin/clang" --version | head -1
# The native build creates the runtime/PKG; game data is supplied separately by the owner.
# Keep an empty payload directory when no local ISO has been staged.
mkdir -p "$LR_PAYLOAD"
ls -la "$LR_PAYLOAD"
