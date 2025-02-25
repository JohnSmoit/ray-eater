set(RAY_EATER_SOURCES
    "lib/lib.c"
    "lib/platform/utils_${PLATFORM_EXT}.c"
)

message(STATUS "Platform Extension: ${PLATFORM_EXT}")

option(BINARY_BUILD_TYPE "<Specify the type of binary to output>" "SHARED")


add_library(RayEater SHARED
    ${RAY_EATER_SOURCES}
)
# else()
#     message(ERROR_FATAL "Oopsie Poopsie, there's no static option yet heehee")
# endif()
# TODO: Static compilation
set(BUILD_PLATFORM_LABEL "${CMAKE_SYSTEM_NAME}:${CMAKE_SYSTEM_PROCESSOR} -- Compiled Using ${CMAKE_C_COMPILER_ID} ${CMAKE_C_COMPILER_VERSION}")
configure_file(lib/platform/info.h.in ../../include/info.h)

target_include_directories(RayEater PUBLIC
    "src/lib"
    "../include"
) #FIXME: THIS DOES NOT WORK FOR HEADER INCLUDES AAAAAAAH

set(CMAKE_C_FLAGS "${CMAKE_CXX_FLAGS} -Wall -O2")

if (UNIX)
    message(STATUS "AAAAAAAAAAAAAAAAAAAAAAAAHHHHHHHHH")
    set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -rdynamic")
endif()

set_target_properties(RayEater PROPERTIES
	C_STANDARD 99
    C_STANDARD_REQUIRED YES
    C_EXTENSIONS YES
    RUNTIME_OUTPUT_DIRECTORY_DEBUG ../../bin
)