set(REXGLUE_USE_VULKAN ON CACHE BOOL "" FORCE)
set(REXGLUE_USE_D3D12 OFF CACHE BOOL "" FORCE)
set(REXGLUE_ENABLE_FIDELITYFX OFF CACHE BOOL "Enable optional FidelityFX temporal providers")
set(REXGLUE_BUILD_TESTS OFF CACHE BOOL "")

if(PS4)
    # Tracy is a desktop profiler built as a shared library with no PS4 port.
    set(REXGLUE_ENABLE_TRACY OFF CACHE BOOL "" FORCE)
endif()

set(REXSDK_DIR "${CMAKE_SOURCE_DIR}/glue/rexglue-sdk-main"
    CACHE PATH "Path to the Graine RexGlue SDK source tree")

if(NOT EXISTS "${REXSDK_DIR}/CMakeLists.txt")
    message(FATAL_ERROR "Graine RexGlue SDK not found at ${REXSDK_DIR}")
endif()

add_subdirectory("${REXSDK_DIR}" "${CMAKE_CURRENT_BINARY_DIR}/rexglue-sdk")

# The macOS consumer must package the workspace MoltenVK build.  The generic
# RexGlue staging code still supplies the Vulkan loader and SDK support files,
# but an installed MoltenVK may not contain the fixes carried by this tree.
if(APPLE AND NOT TARGET MoltenVK)
    add_subdirectory(
        "${CMAKE_SOURCE_DIR}/thirdparty/MoltenVK"
        "${CMAKE_BINARY_DIR}/thirdparty/MoltenVK"
    )
endif()

add_subdirectory("${REXSDK_DIR}/gta4-recomp" "${CMAKE_CURRENT_BINARY_DIR}/gta4-recomp")

# Mesa's PS4 static utility archive uses zlib compression and CRC routines.
# PacBrew installs PS4 portlibs under OPENORBIS/usr; the stock OpenOrbis
# sysroot does not provide zlib in its default -L search path.
if(PS4 AND TARGET GTAIVSetupManager)
    set(PS4_ZLIB_ARCHIVE "$ENV{OPENORBIS}/usr/lib/libz.a")
    if(NOT EXISTS "${PS4_ZLIB_ARCHIVE}")
        message(FATAL_ERROR "PS4 zlib archive not found: ${PS4_ZLIB_ARCHIVE}. Install ps4-openorbis-portlibs.")
    endif()
    target_link_libraries(GTAIVSetupManager PRIVATE "${PS4_ZLIB_ARCHIVE}")
endif()
