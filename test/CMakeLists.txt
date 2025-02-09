cmake_minimum_required(VERSION 3.10)
include(CMakePrintHelpers)

project(RayEater_Tests)

set(CMAKE_C_STANDARD 99)
set(CMAKE_C_STANDARD_REQUIRED True)

add_executable(RayEater_Tests 
    Deliverable_1/main.c
)

target_include_directories(RayEater_Tests PUBLIC
    "${PROJECT_SOURCE_DIR}/"
)