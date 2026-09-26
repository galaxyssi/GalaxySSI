cmake_minimum_required(VERSION 3.22.1)
project(galaxyssi_ar_whisper LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
get_filename_component(WHISPER_ROOT
    "${CMAKE_CURRENT_SOURCE_DIR}/../../../../../android/app/src/main/cpp/whispercpp"
    ABSOLUTE)

set(GGML_NATIVE OFF CACHE BOOL "" FORCE)
set(BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)
set(GGML_BACKEND_DL OFF CACHE BOOL "" FORCE)
set(GGML_CPU_ALL_VARIANTS OFF CACHE BOOL "" FORCE)
set(GGML_OPENMP OFF CACHE BOOL "" FORCE)
set(GGML_BUILD_TESTS OFF CACHE BOOL "" FORCE)
set(GGML_BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
if(ANDROID_ABI STREQUAL "armeabi-v7a")
    # VENUS advertises NEON; the generic ARMv7 compiler target does not enable it.
    add_compile_options(-mfpu=neon)
endif()
add_subdirectory("${WHISPER_ROOT}/ggml" "${CMAKE_CURRENT_BINARY_DIR}/ggml")

foreach(GGML_TARGET ggml ggml-base ggml-cpu)
    if(TARGET ${GGML_TARGET})
        target_compile_options(${GGML_TARGET} PRIVATE -O3)
    endif()
endforeach()

add_library(arwhisper SHARED
    whisper_tiny_jni.cpp
    "${WHISPER_ROOT}/src/whisper.cpp")
target_compile_definitions(arwhisper PRIVATE GGML_USE_CPU WHISPER_VERSION="1.9.1")
target_compile_options(arwhisper PRIVATE -O3 -fvisibility=hidden -fvisibility-inlines-hidden)
target_include_directories(arwhisper PRIVATE
    "${WHISPER_ROOT}"
    "${WHISPER_ROOT}/include"
    "${WHISPER_ROOT}/src"
    "${WHISPER_ROOT}/ggml/include"
    "${WHISPER_ROOT}/ggml/src"
    "${WHISPER_ROOT}/ggml/src/ggml-cpu")
find_library(LOG_LIB log)
target_link_libraries(arwhisper PRIVATE ${LOG_LIB} ggml)
