# Compatibility shim for dependencies that still call find_package(PythonInterp).
# CMake 4 removed FindPythonInterp; use the supported FindPython3 module instead.

include(FindPython3)

if(Python3_Interpreter_FOUND)
    set(PYTHONINTERP_FOUND TRUE)
    set(PYTHON_EXECUTABLE "${Python3_EXECUTABLE}")
    set(PYTHON_VERSION_STRING "${Python3_VERSION}")
    set(PYTHON_VERSION_MAJOR "${Python3_VERSION_MAJOR}")
    set(PYTHON_VERSION_MINOR "${Python3_VERSION_MINOR}")
    set(PYTHON_VERSION_PATCH "${Python3_VERSION_PATCH}")
else()
    set(PYTHONINTERP_FOUND FALSE)
endif()

include(FindPackageHandleStandardArgs)
find_package_handle_standard_args(
    PythonInterp
    REQUIRED_VARS PYTHON_EXECUTABLE
    VERSION_VAR PYTHON_VERSION_STRING
)

mark_as_advanced(PYTHON_EXECUTABLE)
