cmake_minimum_required(VERSION 3.10)
# General TODO: We need better support for cross-platform builds
# containing OS-specific code.
# General TODO: Add support for Cmake files in each testing folder,
# since some tests may require a more complex build process than
# just globbing all the files.

set(CMAKE_C_STANDARD 99)
set(CMAKE_C_STANDARD_REQUIRED True)

option(TEST_ROOT "<test-folder>" "Deliverable_1")



if(TEST_ROOT MATCHES "^\.+[\/\\]*shared[\/\\]*$")
    message(FATAL_ERROR "Shared is not a compilable test. It only contains shared code used by most tests")
elseif(NOT TEST_ROOT)
    message(FATAL_ERROR "Must specify one or more tests to build/execute.")
endif()

# CMake Files in testing subdirectories can define 
# extra options for how they should build. (TODO)
# add_subdirectory("${TEST_ROOT}")

include(shared/CMakeLists.txt)
include(${TEST_ROOT}/CMakeLists.txt)

# platform files need to be globbed separately

message(STATUS "root: ${TEST_ROOT}")
message(STATUS "Files: ${TestSourceFiles}")

add_executable(RayEater_Tests 
    ${TestSourceFiles}
    ${SharedSourceFiles}
)

# add_custom_command(TARGET RayEater_Tests POST_BUILD        # Adds a post-build event to MyTest
#     COMMAND ${CMAKE_COMMAND} -E copy_if_different  # which executes "cmake - E copy_if_different..."
#         "${PROJECT_SOURCE_DIR}/build/test/Debug/RayEater_Tests.dll"      # <--this is in-file
#         $<TARGET_FILE_DIR:RayEater>
# )

# Since any part of the code may need testing, we make all
# files available to the compiler.
target_include_directories(RayEater_Tests PUBLIC
    "./"
    "../include/"
    "../src/lib/"
    "../src/rsh/"
)

get_target_property(LOG_INCLUDES RayEater_Tests INCLUDE_DIRECTORIES)
message(STATUS "Testing Includes: ${LOG_INCLUDES}")