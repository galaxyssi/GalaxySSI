cmake_minimum_required(VERSION 3.20)

project(galaxyssi-whisper-ios LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)
set(GGML_NATIVE OFF CACHE BOOL "" FORCE)
set(GGML_BACKEND_DL OFF CACHE BOOL "" FORCE)
set(GGML_CPU_ALL_VARIANTS OFF CACHE BOOL "" FORCE)
set(GGML_CPU_ARM_ARCH "" CACHE STRING "" FORCE)
set(GGML_OPENMP OFF CACHE BOOL "" FORCE)
set(GGML_METAL OFF CACHE BOOL "" FORCE)
set(GGML_ACCELERATE ON CACHE BOOL "" FORCE)
set(WHISPER_USE_SYSTEM_GGML OFF CACHE BOOL "" FORCE)
set(WHISPER_BUILD_TESTS OFF CACHE BOOL "" FORCE)
set(WHISPER_BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
set(WHISPER_BUILD_SERVER OFF CACHE BOOL "" FORCE)
set(WHISPER_COREML OFF CACHE BOOL "" FORCE)

set(WHISPER_SOURCE_DIR
  "${CMAKE_CURRENT_LIST_DIR}/../../android/app/src/main/cpp/whispercpp"
  CACHE PATH "Pinned whisper.cpp source directory")
if(NOT EXISTS "${WHISPER_SOURCE_DIR}/include/whisper.h")
  message(FATAL_ERROR "Pinned whisper.cpp source is missing; initialize Git submodules")
endif()

add_subdirectory("${WHISPER_SOURCE_DIR}" whisper-build EXCLUDE_FROM_ALL)

# Keep CPU inference optimized in Debug builds too. iOS uses one statically
# linked CPU runtime and never scans device-specific backend modules.
foreach(GGML_TARGET ggml ggml-base ggml-cpu)
  if(TARGET ${GGML_TARGET})
    target_compile_options(${GGML_TARGET} PRIVATE -O3)
  endif()
endforeach()

add_library(galaxyssi-whisper STATIC galaxyssi_whisper.cpp)
target_include_directories(galaxyssi-whisper PRIVATE
  "${CMAKE_CURRENT_LIST_DIR}"
  "${WHISPER_SOURCE_DIR}/include"
  "${WHISPER_SOURCE_DIR}/src"
  "${WHISPER_SOURCE_DIR}/ggml/include"
  "${WHISPER_SOURCE_DIR}/ggml/src"
)
target_compile_features(galaxyssi-whisper PRIVATE cxx_std_17)
target_compile_options(galaxyssi-whisper PRIVATE -O3 -fvisibility=hidden)
target_link_libraries(galaxyssi-whisper PRIVATE whisper)
set_target_properties(galaxyssi-whisper PROPERTIES OUTPUT_NAME galaxyssi-whisper)
