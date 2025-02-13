cmake_minimum_required(VERSION 3.10)

project(RayEater
    VERSION 0.0.1.1
    DESCRIPTION "A standalone Raytracing renderer"
    LANGUAGES C
)
# stuff to help debug cmake
message(STATUS "cmake tool chain: ${CMAKE_TOOLCHAIN_FILE}")
message(STATUS "cmake source dir: ${CMAKE_SOURCE_DIR}")
message(STATUS "library postfix: ${CMAKE_DEBUG_POSTFIX}")
message(STATUS "CMake C compiler: ${CMAKE_C_COMPILER_ID}")
message(STATUS "CMake C++ compiler: ${CMAKE_CXX_COMPILER_ID}")
message(STATUS "CMake system name: ${CMAKE_SYSTEM_NAME}")
message(STATUS "CMake host system processor: ${CMAKE_HOST_SYSTEM_PROCESSOR}")

set(CMAKE_ARCHIVE_OUTPUT_DIRECTORY ${CMAKE_SOURCE_DIR}/lib)
set(CMAKE_LIBRARY_OUTPUT_DIRECTORY ${CMAKE_SOURCE_DIR}/bin)
set(CMAKE_RUNTIME_OUTPUT_DIRECTORY ${CMAKE_SOURCE_DIR}/bin)



add_subdirectory(src)

option(BUILD_TESTS "<build the Ray Eater testing suite>" OFF)
if (BUILD_TESTS)
    add_subdirectory(test)
endif()
