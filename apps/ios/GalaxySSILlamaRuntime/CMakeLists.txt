cmake_minimum_required(VERSION 3.20)

project(galaxyssi-llama-ios LANGUAGES C CXX OBJC OBJCXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)
set(GGML_NATIVE OFF CACHE BOOL "" FORCE)
set(GGML_BACKEND_DL OFF CACHE BOOL "" FORCE)
set(GGML_OPENMP OFF CACHE BOOL "" FORCE)
set(GGML_RPC OFF CACHE BOOL "" FORCE)
set(GGML_CUDA OFF CACHE BOOL "" FORCE)
set(GGML_VULKAN OFF CACHE BOOL "" FORCE)
set(GGML_OPENCL OFF CACHE BOOL "" FORCE)
set(GGML_SYCL OFF CACHE BOOL "" FORCE)
set(GGML_METAL ON CACHE BOOL "" FORCE)
set(GGML_METAL_EMBED_LIBRARY ON CACHE BOOL "" FORCE)
set(GGML_ACCELERATE ON CACHE BOOL "" FORCE)
set(LLAMA_BUILD_COMMON OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_TESTS OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_SERVER OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_APP OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_TOOLS OFF CACHE BOOL "" FORCE)

set(LLAMA_SOURCE_DIR "${CMAKE_CURRENT_LIST_DIR}/../../android/third_party/llama.cpp" CACHE PATH
  "Pinned llama.cpp source directory")
if(NOT EXISTS "${LLAMA_SOURCE_DIR}/include/llama.h")
  message(FATAL_ERROR "Pinned llama.cpp submodule is missing; initialize Git submodules")
endif()

add_subdirectory("${LLAMA_SOURCE_DIR}" llama-build EXCLUDE_FROM_ALL)

# iOS uses one statically linked llama.cpp runtime. Keep CPU kernels optimized
# in Debug builds as well, while leaving device-specific backends out of the
# runtime and behind the platform's supported Metal/Accelerate path.
foreach(GGML_TARGET ggml ggml-base ggml-cpu)
  if(TARGET ${GGML_TARGET})
    target_compile_options(${GGML_TARGET} PRIVATE -O3)
  endif()
endforeach()

add_library(galaxyssi-llama STATIC galaxyssi_llama.mm)
target_include_directories(galaxyssi-llama PRIVATE
  "${CMAKE_CURRENT_LIST_DIR}"
  "${LLAMA_SOURCE_DIR}/include"
  "${LLAMA_SOURCE_DIR}/ggml/include"
)
target_compile_features(galaxyssi-llama PRIVATE cxx_std_17)
target_link_libraries(galaxyssi-llama PRIVATE llama)
set_target_properties(galaxyssi-llama PROPERTIES OUTPUT_NAME galaxyssi-llama)
