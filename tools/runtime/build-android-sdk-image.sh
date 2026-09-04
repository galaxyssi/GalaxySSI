#!/usr/bin/env bash
set -euo pipefail

android_sdk_version="36.0.0"
android_platform_archive="platform-36_r02.zip"
android_platform_sha256="37607369a28c5b640b3a7998868d45898ebcb777565a0e85f9acf36f29631d2e"
android_build_tools_archive="build-tools_r36_linux.zip"
android_build_tools_sha256="5d9ac77fb6ff43d9da518a337b4fcf8f9097113df531d99ccefe80ef7ce8250b"
android_build_tools_source_commit="c4edf8539a34a8600538e6642c1ecb170452a79e"

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repository_root="$(cd "$script_dir/../.." && pwd)"
source "$script_dir/runtime-download.sh"
work_root="${GALAXYSSI_RUNTIME_BUILD_DIR:-$repository_root/build/runtime/android-sdk}"
download_dir="${GALAXYSSI_RUNTIME_DOWNLOAD_DIR:-$repository_root/build/runtime/downloads}"
output="${1:-$repository_root/build/runtime/release/android-sdk-$android_sdk_version-arm64-v8a.img}"

if [[ "$(uname -s)" != "Linux" ]]; then
  echo "The Android SDK image must be built on Linux." >&2
  exit 2
fi
for command in curl docker file node realpath sha256sum unzip; do
  command -v "$command" >/dev/null || {
    echo "Missing build dependency: $command" >&2
    exit 2
  }
done

repository_root="$(realpath -m "$repository_root")"
work_root="$(realpath -m "$work_root")"
download_dir="$(realpath -m "$download_dir")"
output="$(realpath -m "$output")"
if [[ -z "$work_root" || "$work_root" == "/" || "$work_root" == "$repository_root" ]]; then
  echo "Refusing to use an unsafe runtime build directory." >&2
  exit 2
fi

mkdir -p "$download_dir" "$work_root" "$(dirname "$output")"
platform_archive="$download_dir/$android_platform_archive"
build_tools_archive="$download_dir/$android_build_tools_archive"
download_verified_runtime_input \
  "https://dl.google.com/android/repository/$android_platform_archive" \
  "$platform_archive" \
  "$android_platform_sha256" \
  "Android platform 36 revision 2"
download_verified_runtime_input \
  "https://dl.google.com/android/repository/$android_build_tools_archive" \
  "$build_tools_archive" \
  "$android_build_tools_sha256" \
  "Android build tools $android_sdk_version"

source_root="$work_root/source-root"
native_root="$work_root/native-root"
unpacked_root="$work_root/unpacked"
rm -rf "$source_root" "$native_root" "$unpacked_root"
mkdir -p "$source_root/bin" "$source_root/sdk/build-tools/$android_sdk_version" \
  "$source_root/sdk/platforms/android-36" "$native_root" "$unpacked_root/platform" \
  "$unpacked_root/build-tools"

unzip -q "$platform_archive" -d "$unpacked_root/platform"
platform_root="$(dirname "$(find "$unpacked_root/platform" -type f -name android.jar -print -quit)")"
[[ -n "$platform_root" && -f "$platform_root/android.jar" ]] || {
  echo "Android platform archive layout is invalid." >&2
  exit 2
}
cp -a "$platform_root/." "$source_root/sdk/platforms/android-36/"

unzip -q "$build_tools_archive" -d "$unpacked_root/build-tools"
build_tools_root="$(dirname "$(find "$unpacked_root/build-tools" -type f -name d8 -print -quit)")"
[[ -n "$build_tools_root" && -f "$build_tools_root/lib/d8.jar" ]] || {
  echo "Android build tools archive layout is invalid." >&2
  exit 2
}
cp -a "$build_tools_root/." "$source_root/sdk/build-tools/$android_sdk_version/"

docker run --rm --platform linux/arm64 \
  -e "SOURCE_COMMIT=$android_build_tools_source_commit" \
  -e "HOST_UID=$(id -u)" \
  -e "HOST_GID=$(id -g)" \
  -v "$native_root:/out" \
  ubuntu:24.04 bash -euo pipefail -c '
    export DEBIAN_FRONTEND=noninteractive
    apt-get update
    apt-get install --yes --no-install-recommends \
      bison build-essential ca-certificates cmake flex git libexpat1-dev libfmt-dev \
      libgtest-dev libpng-dev libprotobuf-dev ninja-build pkg-config protobuf-compiler zlib1g-dev
    git clone --filter=blob:none https://github.com/termux/android-build-tools.git /tmp/android-build-tools
    cd /tmp/android-build-tools
    git checkout --detach "$SOURCE_COMMIT"
    git submodule update --init --recursive
    cmake -B build -G Ninja -DCMAKE_BUILD_TYPE=Release
    cmake --build build --parallel
    mkdir -p /out/libexec /out/lib
    for tool in aapt aapt2 aidl zipalign; do
      install -m 0755 "build/vendor/$tool" "/out/libexec/$tool"
      ldd "build/vendor/$tool" | awk '\''/=> \// { print $3 } /^\// { print $1 }'\''
    done | sort -u | while read -r library; do
      case "$(basename "$library")" in
        ld-linux-aarch64.so.1|libc.so.6|libdl.so.2|libm.so.6|libpthread.so.0|librt.so.1) continue ;;
      esac
      cp -L "$library" "/out/lib/$(basename "$library")"
    done
    chown -R "$HOST_UID:$HOST_GID" /out
  '

for tool in aapt aapt2 aidl zipalign; do
  file "$native_root/libexec/$tool" | grep -q 'ARM aarch64' || {
    echo "Android native build tool is not ARM64: $tool" >&2
    exit 2
  }
  cat >"$source_root/bin/$tool" <<EOF
#!/bin/sh
root="\$(CDPATH= cd -- "\$(dirname -- "\$(readlink -f -- "\$0")")/.." && pwd)"
export LD_LIBRARY_PATH="\$root/lib"
exec "\$root/libexec/$tool" "\$@"
EOF
  chmod 0755 "$source_root/bin/$tool"
  cp "$source_root/bin/$tool" "$source_root/sdk/build-tools/$android_sdk_version/$tool"
done
cp -a "$native_root/libexec" "$native_root/lib" "$source_root/"

for tool in apksigner d8; do
  cat >"$source_root/bin/$tool" <<EOF
#!/bin/sh
root="\$(CDPATH= cd -- "\$(dirname -- "\$(readlink -f -- "\$0")")/.." && pwd)"
exec "\$root/sdk/build-tools/$android_sdk_version/$tool" "\$@"
EOF
  chmod 0755 "$source_root/bin/$tool" "$source_root/sdk/build-tools/$android_sdk_version/$tool"
done

rm -f \
  "$source_root/sdk/build-tools/$android_sdk_version/aapt" \
  "$source_root/sdk/build-tools/$android_sdk_version/aapt2" \
  "$source_root/sdk/build-tools/$android_sdk_version/aidl" \
  "$source_root/sdk/build-tools/$android_sdk_version/zipalign"
for tool in aapt aapt2 aidl zipalign; do
  ln -s "../../../bin/$tool" "$source_root/sdk/build-tools/$android_sdk_version/$tool"
done
rm -f "$source_root/sdk/build-tools/$android_sdk_version"/{dexdump,llvm-rs-cc,split-select}
rm -rf "$source_root/sdk/build-tools/$android_sdk_version/lib64"

cat >"$source_root/NOTICE" <<EOF
Android platform and Java build tools are sourced from the official Android SDK $android_sdk_version.
ARM64 aapt, aapt2, aidl, and zipalign are built from termux/android-build-tools commit
$android_build_tools_source_commit and its pinned AOSP submodules.
EOF

node "$repository_root/tools/runtime/build-runtime-image.mjs" \
  --pack-id android-sdk \
  --version "$android_sdk_version" \
  --source "$source_root" \
  --output "$output" \
  --dependency java \
  --license "Android-SDK-License AND Apache-2.0"
