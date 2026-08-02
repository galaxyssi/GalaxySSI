cmake_minimum_required(VERSION 3.31.6)

project(signalasi-llama LANGUAGES C CXX ASM)

set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

if(ANDROID)
    add_link_options(
        "-Wl,-z,max-page-size=16384"
        "-Wl,-z,common-page-size=16384"
    )
endif()

# Strip only this module at link time. The app keeps symbols for normalized
# QEMU libraries whose 16 KB LOAD layout must not be rewritten by AGP.
set(CMAKE_SHARED_LINKER_FLAGS_RELEASE
    "${CMAKE_SHARED_LINKER_FLAGS_RELEASE} -Wl,--strip-all")

if(NOT ANDROID_ABI STREQUAL "arm64-v8a")
    message(FATAL_ERROR "SignalASI local LLM supports arm64-v8a only")
endif()

set(GGML_SYSTEM_ARCH "ARM")
set(GGML_CPU_KLEIDIAI ON CACHE BOOL "Use KleidiAI kernels" FORCE)
set(GGML_OPENMP ON CACHE BOOL "Use OpenMP" FORCE)
if(CMAKE_HOST_WIN32 AND DEFINED ENV{LOCALAPPDATA})
    set(SIGNALASI_LLAMA_FETCH_DIR "$ENV{LOCALAPPDATA}/SignalASI/llama-fetch")
else()
    set(SIGNALASI_LLAMA_FETCH_DIR "${CMAKE_CURRENT_LIST_DIR}/../../../../build/llama-fetch")
endif()
set(FETCHCONTENT_BASE_DIR "${SIGNALASI_LLAMA_FETCH_DIR}" CACHE PATH
    "Short shared FetchContent path for Android builds" FORCE)

set(LLAMA_SOURCE_DIR "${CMAKE_CURRENT_LIST_DIR}/../../../../third_party/llama.cpp")
if(NOT EXISTS "${LLAMA_SOURCE_DIR}/include/llama.h")
    message(FATAL_ERROR "Pinned llama.cpp submodule is missing; initialize Git submodules")
endif()

add_subdirectory("${LLAMA_SOURCE_DIR}" llama-build)

add_library(signalasi-llama SHARED signalasi_llama.cpp)
target_include_directories(signalasi-llama PRIVATE
    "${LLAMA_SOURCE_DIR}/include"
    "${LLAMA_SOURCE_DIR}/ggml/include"
)
target_link_libraries(signalasi-llama PRIVATE llama android log)
