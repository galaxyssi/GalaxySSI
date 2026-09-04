#!/bin/bash
set -euo pipefail

if [[ "${GALAXYSSI_NATIVE_WHISPER:-1}" != "1" ]]; then
  exit 0
fi

repo_root="$(cd "${SRCROOT}/../.." && pwd)"
source_dir="${repo_root}/apps/android/app/src/main/cpp/whispercpp"
if [[ ! -f "${source_dir}/include/whisper.h" ]]; then
  echo "error: initialize apps/android/app/src/main/cpp/whispercpp before enabling the iOS native Whisper runtime" >&2
  exit 1
fi

output_dir="${DERIVED_FILE_DIR}/GalaxySSIWhisperRuntime"
build_dir="${output_dir}/cmake"
cc="$(xcrun --sdk "${SDKROOT}" --find clang)"
cxx="$(xcrun --sdk "${SDKROOT}" --find clang++)"
mkdir -p "${output_dir}"

cmake -S "${SRCROOT}/GalaxySSIWhisperRuntime" -B "${build_dir}" -G "Unix Makefiles" \
  -DCMAKE_SYSTEM_NAME=iOS \
  -DCMAKE_C_COMPILER="${cc}" \
  -DCMAKE_CXX_COMPILER="${cxx}" \
  -DCMAKE_BUILD_TYPE="${CONFIGURATION}" \
  -DCMAKE_OSX_SYSROOT="${SDKROOT}" \
  -DCMAKE_OSX_ARCHITECTURES="${ARCHS:-arm64}" \
  -DCMAKE_OSX_DEPLOYMENT_TARGET="${IPHONEOS_DEPLOYMENT_TARGET}" \
  -DCMAKE_XCODE_ATTRIBUTE_CODE_SIGNING_ALLOWED=NO \
  -DCMAKE_XCODE_ATTRIBUTE_CODE_SIGNING_REQUIRED=NO
cmake --build "${build_dir}" --target galaxyssi-whisper -- -j1

archives=()
while IFS= read -r archive; do
  archives+=("${archive}")
done < <(find "${build_dir}" -type f -name '*.a' | sort)
if [[ "${#archives[@]}" -lt 2 ]]; then
  echo "error: whisper.cpp did not produce the expected static archives" >&2
  exit 1
fi

rm -f "${output_dir}/libgalaxyssi-whisper.a"
"$(xcrun --find libtool)" -static -o "${output_dir}/libgalaxyssi-whisper.a" "${archives[@]}"
