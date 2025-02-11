cmake_minimum_required(VERSION 3.10)
# General TODO: We need better support for cross-platform builds
# containing OS-specific code.
# General TODO: Add support for Cmake files in each testing folder,
# since some tests may require a more complex build process than
# just globbing all the files.

project(RayEater_Tests)

set(CMAKE_C_STANDARD 99)
set(CMAKE_C_STANDARD_REQUIRED True)

option(TestRoot "<test-folder>" FALSE)



if(TestRoot MATCHES "^\.+[\/\\]*shared[\/\\]*$")
    message(FATAL_ERROR "Shared is not a compilable test. It only contains shared code used by most tests")
elseif(NOT TestRoot)
    message(FATAL_ERROR "Must specify one or more tests to build/execute.")
endif()

# CMake Files in testing subdirectories can define 
# extra options for how they should build. (TODO)
# add_subdirectory("${TestRoot}")

include(shared/CMakeLists.txt)
include(${TestRoot}/CMakeLists.txt)

# platform files need to be globbed separately

message(STATUS "root: ${TestRoot}")
message(STATUS "Files: ${TestSourceFiles}")

add_executable(RayEater_Tests 
    ${TestSourceFiles}
    ${SharedSourceFiles}
)

# Since any part of the code may need testing, we make all
# files available to the compiler.
target_include_directories(RayEater_Tests PUBLIC
    "${PROJECT_SOURCE_DIR}/"
    "../include/"
    "../src/lib/"
    "../src/rsh/"
)