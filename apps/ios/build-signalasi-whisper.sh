#!/bin/bash
set -euo pipefail

if [[ "${SIGNALASI_NATIVE_WHISPER:-1}" != "1" ]]; then
  exit 0
fi

repo_root="$(cd "${SRCROOT}/../.." && pwd)"
source_dir="${repo_root}/apps/android/app/src/main/cpp/whispercpp"
if [[ ! -f "${source_dir}/include/whisper.h" ]]; then
  echo "error: initialize apps/android/app/src/main/cpp/whispercpp before enabling the iOS native Whisper runtime" >&2
  exit 1
fi

output_dir="${DERIVED_FILE_DIR}/SignalASIWhisperRuntime"
build_dir="${output_dir}/cmake"
mkdir -p "${output_dir}"

cmake -S "${SRCROOT}/SignalASIWhisperRuntime" -B "${build_dir}" -G Xcode \
  -DCMAKE_SYSTEM_NAME=iOS \
  -DCMAKE_OSX_SYSROOT="${SDKROOT}" \
  -DCMAKE_OSX_ARCHITECTURES="${ARCHS}" \
  -DCMAKE_OSX_DEPLOYMENT_TARGET="${IPHONEOS_DEPLOYMENT_TARGET}" \
  -DCMAKE_XCODE_ATTRIBUTE_CODE_SIGNING_ALLOWED=NO \
  -DCMAKE_XCODE_ATTRIBUTE_CODE_SIGNING_REQUIRED=NO
cmake --build "${build_dir}" --config "${CONFIGURATION}" --target signalasi-whisper

archives=()
while IFS= read -r archive; do
  archives+=("${archive}")
done < <(find "${build_dir}" -type f -name '*.a' | sort)
if [[ "${#archives[@]}" -lt 2 ]]; then
  echo "error: whisper.cpp did not produce the expected static archives" >&2
  exit 1
fi

rm -f "${output_dir}/libsignalasi-whisper.a"
"$(xcrun --find libtool)" -static -o "${output_dir}/libsignalasi-whisper.a" "${archives[@]}"
