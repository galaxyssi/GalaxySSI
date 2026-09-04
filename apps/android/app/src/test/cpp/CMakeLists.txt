cmake_minimum_required(VERSION 3.22.1)
project(galaxyssi_asr_native_tests LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
enable_testing()

add_subdirectory(../../main/cpp/asr galaxyssi-asr)

add_executable(galaxyssi_asr_frontend_tests asr_frontend_tests.cpp)
target_link_libraries(galaxyssi_asr_frontend_tests PRIVATE galaxyssi_asr_core)
target_compile_options(galaxyssi_asr_frontend_tests PRIVATE -Wall -Wextra -Wpedantic)

add_test(NAME galaxyssi_asr_frontend_tests COMMAND galaxyssi_asr_frontend_tests)
