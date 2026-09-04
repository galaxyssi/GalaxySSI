#!/bin/bash
set -euo pipefail

if [[ "${GALAXYSSI_NATIVE_LLAMA:-1}" != "1" ]]; then
  exit 0
fi

repo_root="$(cd "${SRCROOT}/../.." && pwd)"
source_dir="${repo_root}/apps/android/third_party/llama.cpp"
if [[ ! -f "${source_dir}/include/llama.h" ]]; then
  echo "error: initialize apps/android/third_party/llama.cpp before enabling the iOS native model runtime" >&2
  exit 1
fi

output_dir="${DERIVED_FILE_DIR}/GalaxySSILlamaRuntime"
build_dir="${output_dir}/cmake"
cc="$(xcrun --sdk "${SDKROOT}" --find clang)"
cxx="$(xcrun --sdk "${SDKROOT}" --find clang++)"
mkdir -p "${output_dir}"

cmake -S "${SRCROOT}/GalaxySSILlamaRuntime" -B "${build_dir}" -G "Unix Makefiles" \
  -DCMAKE_SYSTEM_NAME=iOS \
  -DCMAKE_C_COMPILER="${cc}" \
  -DCMAKE_CXX_COMPILER="${cxx}" \
  -DCMAKE_BUILD_TYPE="${CONFIGURATION}" \
  -DCMAKE_OSX_SYSROOT="${SDKROOT}" \
  -DCMAKE_OSX_ARCHITECTURES="${ARCHS:-arm64}" \
  -DCMAKE_OSX_DEPLOYMENT_TARGET="${IPHONEOS_DEPLOYMENT_TARGET}" \
  -DCMAKE_XCODE_ATTRIBUTE_CODE_SIGNING_ALLOWED=NO \
  -DCMAKE_XCODE_ATTRIBUTE_CODE_SIGNING_REQUIRED=NO

cache_file="${build_dir}/CMakeCache.txt"
for required_setting in \
  'BUILD_SHARED_LIBS:BOOL=OFF' \
  'GGML_BACKEND_DL:BOOL=OFF' \
  'GGML_RPC:BOOL=OFF' \
  'GGML_CUDA:BOOL=OFF' \
  'GGML_VULKAN:BOOL=OFF' \
  'GGML_OPENCL:BOOL=OFF' \
  'GGML_SYCL:BOOL=OFF'; do
  if ! grep -q "^${required_setting}$" "${cache_file}"; then
    echo "error: unsafe iOS local-model runtime setting: ${required_setting}" >&2
    exit 1
  fi
done
cmake --build "${build_dir}" --target galaxyssi-llama -- -j1

archives=()
while IFS= read -r archive; do
  archives+=("${archive}")
done < <(find "${build_dir}" -type f -name '*.a' | sort)
if [[ "${#archives[@]}" -lt 2 ]]; then
  echo "error: llama.cpp did not produce the expected static archives" >&2
  exit 1
fi

rm -f "${output_dir}/libgalaxyssi-llama.a"
"$(xcrun --find libtool)" -static -o "${output_dir}/libgalaxyssi-llama.a" "${archives[@]}"

symbols_file="${output_dir}/libgalaxyssi-llama.symbols"
"$(xcrun --find nm)" -gU "${output_dir}/libgalaxyssi-llama.a" > "${symbols_file}"
if grep -Eiq '(qnn|hexagon|htp|genie)' "${symbols_file}"; then
  echo "error: incompatible accelerator symbols found in the iOS GGUF runtime" >&2
  exit 1
fi
rm -f "${symbols_file}"
