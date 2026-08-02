cmake_minimum_required(VERSION 3.22.1)
project(signalasi_asr_native_tests LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
enable_testing()

add_subdirectory(../../main/cpp/asr signalasi-asr)

add_executable(signalasi_asr_frontend_tests asr_frontend_tests.cpp)
target_link_libraries(signalasi_asr_frontend_tests PRIVATE signalasi_asr_core)
target_compile_options(signalasi_asr_frontend_tests PRIVATE -Wall -Wextra -Wpedantic)

add_test(NAME signalasi_asr_frontend_tests COMMAND signalasi_asr_frontend_tests)
