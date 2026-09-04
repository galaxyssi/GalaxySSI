cmake_minimum_required(VERSION 3.22.1)
project(galaxyssi_whisper LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(WHISPER_ROOT ${CMAKE_CURRENT_SOURCE_DIR}/whispercpp)

if(ANDROID)
    add_link_options(
        "-Wl,-z,max-page-size=16384"
        "-Wl,-z,common-page-size=16384"
    )
endif()

set(GGML_NATIVE OFF CACHE BOOL "" FORCE)
# Whisper owns a pinned GGML revision that is intentionally different from
# GenieX. Link that revision into libwhisper instead of publishing generic
# libggml*.so files that Android could bind to GenieX's newer libllama.so.
set(BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)
set(GGML_BACKEND_DL OFF CACHE BOOL "" FORCE)
set(GGML_CPU_ALL_VARIANTS OFF CACHE BOOL "" FORCE)
set(GGML_CPU_ARM_ARCH "" CACHE STRING "" FORCE)
set(GGML_OPENMP OFF CACHE BOOL "" FORCE)
set(GGML_BUILD_TESTS OFF CACHE BOOL "" FORCE)
set(GGML_BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
add_subdirectory(${WHISPER_ROOT}/ggml ${CMAKE_CURRENT_BINARY_DIR}/ggml)
add_subdirectory(asr)

# Android debug APKs still need release-grade inference kernels. The wrapper
# targets were optimized already, but the actual CPU tensor implementation was
# previously left at the debug toolchain default.
foreach(GGML_TARGET ggml ggml-base ggml-cpu)
    if(TARGET ${GGML_TARGET})
        target_compile_options(${GGML_TARGET} PRIVATE -O3)
    endif()
endforeach()

add_library(whisper SHARED
    whisper_jni.c
    whisper_jni_v2.cpp
    ${WHISPER_ROOT}/src/whisper.cpp
)

target_compile_definitions(whisper PRIVATE
    GGML_USE_CPU
    WHISPER_VERSION="1.9.1"
)
target_compile_options(whisper PRIVATE
    -O3
    -fvisibility=hidden
    -fvisibility-inlines-hidden
)
target_include_directories(whisper PRIVATE
    ${WHISPER_ROOT}
    ${WHISPER_ROOT}/include
    ${WHISPER_ROOT}/src
    ${WHISPER_ROOT}/ggml/include
    ${WHISPER_ROOT}/ggml/src
    ${WHISPER_ROOT}/ggml/src/ggml-cpu
)

find_library(LOG_LIB log)
find_library(ANDROID_LIB android)

# GenieX scans GGML backends through the dynamic-loader ABI. Qualcomm's
# packaged Hexagon backend exposes its registry function but not the generic
# ggml_backend_init entry point, so publish a tiny adapter without duplicating
# the vendor implementation.
add_library(ggml-hexagon-dl SHARED ggml_hexagon_dl_adapter.c)
target_compile_options(ggml-hexagon-dl PRIVATE -O2 -fvisibility=hidden)
target_link_libraries(ggml-hexagon-dl PRIVATE ${LOG_LIB} ${CMAKE_DL_LIBS})

target_link_libraries(whisper PRIVATE ${LOG_LIB} ${ANDROID_LIB} ${CMAKE_DL_LIBS} ggml)
