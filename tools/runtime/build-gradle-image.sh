#!/usr/bin/env bash
set -euo pipefail

gradle_version="8.14.5"
gradle_archive_sha256="6f74b601422d6d6fc4e1f9a1ab6522f642c2fdcbc15ae33ebd30ba3d7198e854"

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repository_root="$(cd "$script_dir/../.." && pwd)"
source "$script_dir/runtime-download.sh"
work_root="${GALAXYSSI_RUNTIME_BUILD_DIR:-$repository_root/build/runtime/gradle}"
download_dir="${GALAXYSSI_RUNTIME_DOWNLOAD_DIR:-$repository_root/build/runtime/downloads}"
output="${1:-$repository_root/build/runtime/release/gradle-$gradle_version-arm64-v8a.img}"

if [[ "$(uname -s)" != "Linux" ]]; then
  echo "The Gradle image must be built on Linux." >&2
  exit 2
fi
for command in curl sha256sum unzip node realpath; do
  command -v "$command" >/dev/null || {
    echo "Missing build dependency: $command" >&2
    exit 2
  }
done

repository_root="$(realpath -m "$repository_root")"
work_root="$(realpath -m "$work_root")"
download_dir="$(realpath -m "$download_dir")"
output="$(realpath -m "$output")"
archive_name="gradle-$gradle_version-bin.zip"
archive="$download_dir/$archive_name"
if [[ -z "$work_root" || "$work_root" == "/" || "$work_root" == "$repository_root" ]]; then
  echo "Refusing to use an unsafe runtime build directory." >&2
  exit 2
fi

mkdir -p "$download_dir" "$work_root" "$(dirname "$output")"
download_verified_runtime_input \
  "https://services.gradle.org/distributions/$archive_name" \
  "$archive" \
  "$gradle_archive_sha256" \
  "Gradle $gradle_version"

source_root="$work_root/source-root"
unpacked_root="$work_root/unpacked"
rm -rf "$source_root" "$unpacked_root"
mkdir -p "$source_root" "$unpacked_root"
unzip -q "$archive" -d "$unpacked_root"
cp -a "$unpacked_root/gradle-$gradle_version/." "$source_root/"
rm -rf "$unpacked_root"

node "$repository_root/tools/runtime/build-runtime-image.mjs" \
  --pack-id gradle \
  --version "$gradle_version" \
  --source "$source_root" \
  --output "$output" \
  --dependency java \
  --license "Apache-2.0"
