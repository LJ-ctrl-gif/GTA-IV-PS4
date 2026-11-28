#!/usr/bin/env bash
# Read-only validation of the complete native PS4 build environment.
set -uo pipefail
HERE="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/ps4-env.sh"

errors=0
fail() { echo "MISSING: $*" >&2; errors=$((errors + 1)); }
need_command() { command -v "$1" >/dev/null 2>&1 || fail "host command '$1'"; }
need_file() { [[ -f "$1" ]] || fail "file $1"; }
need_dir() { [[ -d "$1" ]] || fail "directory $1"; }

if [[ "$(uname -s)" != Linux || "$(uname -m)" != x86_64 ]]; then
    fail "Linux x86_64 host (detected $(uname -s)/$(uname -m))"
fi

for tool in cmake ninja python3 git curl tar clang-21 clang++-21 ld.lld-21 llvm-ar-21 llvm-ranlib-21 llvm-nm-21 llvm-objcopy-21 llvm-strip-21; do
    need_command "$tool"
done

if command -v cmake >/dev/null 2>&1; then
    cmake_version="$(cmake --version | head -1 | sed -E 's/.* ([0-9]+\.[0-9]+).*/\1/')"
    if [[ -n "$cmake_version" ]] && ! printf '%s\n' 3.29 "$cmake_version" | sort -V -C; then
        fail "CMake 3.29 or newer (found $cmake_version)"
    fi
fi

need_dir "$LR_SRC"
need_file "$LR_SRC/CMakeLists.txt"
need_file "$LR_SRC/CMakePresets.json"
need_dir "$LR_SRC/glue/rexglue-sdk-main/thirdparty"
need_dir "$DOLPHIN_BUILD/src/dolphin/Externals/glslang/glslang"

need_file "$OPENORBIS/bin/ld.lld"
need_file "$OPENORBIS/bin/create-fself"
need_file "$OPENORBIS/link.x"
need_file "$OPENORBIS/lib/crt1.o"
need_file "$OPENORBIS/lib/libclang_rt.builtins-x86_64.a"
need_dir "$OPENORBIS/include"
need_dir "$OPENORBIS/lib"

need_file "$DOLPHIN_SYSROOT/include/c++/v1/__config_site"
need_file "$DOLPHIN_SYSROOT/lib/libc++.a"
need_file "$DOLPHIN_SYSROOT/lib/libc++abi.a"
need_dir "$DOLPHIN_SYSROOT/libc-overlay"

need_file "$OO_PS4_TOOLCHAIN/link.x"
need_file "$OO_PS4_TOOLCHAIN/lib/libcxx_ps4_compat.a"
need_file "$LR_ROOT/llvm/bin/clang"
need_file "$LR_ROOT/host-tools/bin/spirv-val"
need_file "$LR_ROOT/host-tools/bin/glslangValidator"
need_file "$LR_ROOT/host-tools/dxc/lib/libdxcompiler.so"

# Verify the Mesa archive was built from the pinned, PS4-patched source tree.
# A directory of matching library filenames alone is not enough: the GFX7 MUBUF
# address-mode change is required to avoid the known PS4 GPU hang.
MESA_SOURCE="$LR_ROOT/mesa-src"
need_dir "$MESA_SOURCE"
if [[ -f "$MESA_SOURCE/VERSION" ]]; then
    mesa_version="$(tr -d '[:space:]' < "$MESA_SOURCE/VERSION")"
    [[ "$mesa_version" == "26.0.8" ]] || fail "Mesa source version 26.0.8 (found $mesa_version)"
else
    fail "Mesa source version file $MESA_SOURCE/VERSION"
fi
mesa_aco="$MESA_SOURCE/src/amd/compiler/instruction_selection/aco_select_nir_intrinsics.cpp"
if [[ -f "$mesa_aco" ]]; then
    grep -Fq "mubuf_addr64_global" "$mesa_aco" || fail "PS4 MUBUF addr64 Mesa patch in $mesa_aco"
else
    fail "Mesa ACO source file $mesa_aco"
fi

# The source must also contain the base DolphinPS4 GNM integration, not just
# the GTA IV-specific ACO workaround.
if [[ -f "$MESA_SOURCE/meson.build" ]]; then
    grep -Fq "is_ps4 = cc.get_define('__ORBIS__') != ''" "$MESA_SOURCE/meson.build" \
        || fail "DolphinPS4 PS4 Meson integration in $MESA_SOURCE/meson.build"
else
    fail "Mesa Meson source file $MESA_SOURCE/meson.build"
fi
if [[ -f "$MESA_SOURCE/src/amd/common/ac_ps4_drm.c" ]]; then
    :
else
    fail "DolphinPS4 PS4 AMDGPU winsys source $MESA_SOURCE/src/amd/common/ac_ps4_drm.c"
fi
if [[ -f "$MESA_SOURCE/src/amd/vulkan/radv_cmd_buffer.c" ]]; then
    grep -Fq "#ifdef __PS4__" "$MESA_SOURCE/src/amd/vulkan/radv_cmd_buffer.c" \
        || fail "DolphinPS4 PS4 RADV command-buffer integration"
else
    fail "Mesa RADV command-buffer source $MESA_SOURCE/src/amd/vulkan/radv_cmd_buffer.c"
fi

MESA="$LR_ROOT/mesa-build"
mesa_libraries=(
    src/amd/vulkan/libvulkan_radeon.a
    src/amd/common/libamd_common.a
    src/amd/compiler/libaco.a
    src/amd/addrlib/libaddrlib.a
    src/vulkan/util/libvulkan_util.a
    src/compiler/spirv/libvtn.a
    src/compiler/nir/libnir.a
    src/compiler/libcompiler.a
    src/vulkan/runtime/libvulkan_instance.a
    src/vulkan/runtime/libvulkan_runtime.a
    src/vulkan/wsi/libvulkan_wsi.a
    src/util/libxmlconfig.a
    src/util/libmesa_util.a
    src/util/libmesa_util_simd.a
    src/util/libmesa_util_clflush.a
    src/util/libmesa_util_clflushopt.a
    src/util/libparson.a
    src/util/blake3/libblake3.a
    src/c11/impl/libmesa_util_c11.a
)
for library in "${mesa_libraries[@]}"; do
    need_file "$MESA/$library"
done

if (( errors > 0 )); then
    echo
    echo "PS4 build preflight failed: $errors prerequisite(s) missing."
    echo "Use ps4/README.md to provision OpenOrbis, DolphinPS4 sysroot, shader tools and Mesa."
    exit 1
fi

echo "PS4 build preflight passed."
echo "  Source:       $LR_SRC"
echo "  OpenOrbis:    $OPENORBIS"
echo "  DolphinPS4:   $DOLPHIN_BUILD"
echo "  Sysroot:      $DOLPHIN_SYSROOT"
echo "  Mesa archive: $MESA"
echo "  Host tools:   $LR_ROOT/host-tools"
