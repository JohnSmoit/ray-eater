cmake_minimum_required(VERSION 3.10)

include(CTest)

# General TODO: We need better support for cross-platform builds
# containing OS-specific code.
# General TODO: Add support for Cmake files in each testing folder,
# since some tests may require a more complex build process than
# just globbing all the files.

set(CMAKE_C_STANDARD 99)
set(CMAKE_C_STANDARD_REQUIRED True)

option(TEST_GROUPS "<test-folder>" Off)

message(STATUS "Platform Extension: ${PLATFORM_EXT}")


if(TEST_GROUPS MATCHES "^\.+[\/\\]*shared[\/\\]*$")
    message(FATAL_ERROR "Shared is not a compilable test. It only contains shared code used by most tests")
elseif(NOT TEST_GROUPS)
    message(FATAL_ERROR "Must specify one or more testing groups to build/execute.")
endif()

# CMake Files in testing subdirectories can define 
# extra options for how they should build. (TODO)
# add_subdirectory("${TEST_ROOT}")

include(shared/CMakeLists.txt)

message(STATUS "selected groups: ${TEST_GROUPS}")

set(TEST_SOURCES "")
function(ADD_TEST_SOURCES)
    cmake_parse_arguments(PARSE_ARGV 0 ARG
        ""
        ""
        "SOURCES;FILE"
    )
    
    set(TEST_SOURCES ${TEST_SOURCES} ${ARG_FILE} PARENT_SCOPE)
endfunction()

# include specified testing groups
foreach(GROUP IN LISTS TEST_GROUPS)
    include("./${GROUP}/CMakeLists.txt")
endforeach()

message(STATUS "Selected Sources: ${TEST_SOURCES}")

create_test_sourcelist(Tests ray_tests.c "${TEST_SOURCES}")
add_executable(RayEater_Tests ${Tests} ${SharedSourceFiles})

message(STATUS "RayEater_Tests Sourcelist: ${Tests}")

target_link_libraries(RayEater_Tests PUBLIC RayEater)

foreach(test ${TEST_SOURCES})
    get_filename_component(TEST_FILE_NAME ${test} NAME_WE)
    get_filename_component(TEST_FILE_DIR ${test} DIRECTORY)

    set(TEST_NAME "${TEST_FILE_DIR}/${TEST_FILE_NAME}")
    message(STATUS "Adding Test ${TEST_NAME} -- file ${test}!")
    add_test(NAME ${TEST_NAME} COMMAND RayEater_Tests ${TEST_NAME})
endforeach()


# Since any part of the code may need testing, we make all
# files available to the compiler.
target_include_directories(RayEater_Tests PUBLIC
    "${CMAKE_SOURCE_DIR}/test"
    "${CMAKE_SOURCE_DIR}/include/"
    "${CMAKE_SOURCE_DIR}/src/lib/"
    "${CMAKE_SOURCE_DIR}/src/rsh/"
)

