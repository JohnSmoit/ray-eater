
if (WIN32)
    set(PLATFORM_EXT "Win32")
else()
    set(PLATFORM_EXT "NOT_SUPPORTED")
endif()

set(RAY_EATER_SOURCES
    "lib/lib.c"
    "lib/platform/utils_${PLATFORM_EXT}.c"
)

set(CMAKE_EXE_LINKER_FLAGS "${CMAKE_EXE_LINKER_FLAGS} /INCREMENTAL:NO")

option(BINARY_BUILD_TYPE "<Specify the type of binary to output>" "SHARED")


message(STATUS "Type: ${BINARY_BUILD_TYPE}")
if (${BINARY_BUILD_TYPE} STREQUAL "SHARED")
    add_library(RayEater SHARED
        ${RAY_EATER_SOURCES}
    )
else()
    message(ERROR_FATAL "Oopsie Poopsie, there's no static option yet heehee")
endif()
# TODO: Static compilation

target_include_directories(RayEater PUBLIC
    "src/lib"
    "include"
) #FIXME: THIS DOES NOT WORK FOR HEADER INCLUDES AAAAAAAH

set_target_properties(RayEater PROPERTIES
	C_STANDARD 99
    C_STANDARD_REQUIRED YES
    C_EXTENSIONS YES
)

target_compile_options(RayEater PUBLIC "/VERBOSE")