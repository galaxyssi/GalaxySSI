#!/usr/bin/env bash
set -euo pipefail

uv_version="0.11.29"
pack_version="0.12.1"
uv_archive_sha256="593d79a797ece3f1dfaaf3e0a973263422a135d9262c7dbc6cd75d9c11acc0b4"
python_version="3.13.15"
python_release="20260814"
python_archive_sha256="985efd78c1c6521b379f7c64c2a25e6a1130f07441d1af8be441aa05260886aa"
apache_license_sha256="c71d239df91726fc519c6eb72d318ec65820627232b2f796219e87dcf35d0ab4"
mit_license_sha256="860e3d7a86b84e6a7012c7a635fc64df475cebc6cce34dfeb73a5982ec58176c"

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repository_root="$(cd "$script_dir/../.." && pwd)"
source "$script_dir/runtime-download.sh"
work_root="${GALAXYSSI_RUNTIME_BUILD_DIR:-$repository_root/build/runtime/python-uv}"
download_dir="${GALAXYSSI_RUNTIME_DOWNLOAD_DIR:-$repository_root/build/runtime/downloads}"
output="${1:-$repository_root/build/runtime/release/python-uv-$pack_version-arm64-v8a.img}"
archive="$download_dir/uv-aarch64-unknown-linux-musl-$uv_version.tar.gz"
python_archive="$download_dir/cpython-$python_version+$python_release-aarch64-unknown-linux-gnu-install_only_stripped.tar.gz"
apache_license="$download_dir/uv-$uv_version-LICENSE-APACHE"
mit_license="$download_dir/uv-$uv_version-LICENSE-MIT"

if [[ "$(uname -s)" != "Linux" ]]; then
  echo "The python-uv image must be built on Linux." >&2
  exit 2
fi
for command in curl sha256sum tar install node realpath mv cp unsquashfs; do
  command -v "$command" >/dev/null || {
    echo "Missing build dependency: $command" >&2
    exit 2
  }
done

repository_root="$(realpath -m "$repository_root")"
work_root="$(realpath -m "$work_root")"
download_dir="$(realpath -m "$download_dir")"
output="$(realpath -m "$output")"
archive="$download_dir/uv-aarch64-unknown-linux-musl-$uv_version.tar.gz"
python_archive="$download_dir/cpython-$python_version+$python_release-aarch64-unknown-linux-gnu-install_only_stripped.tar.gz"
apache_license="$download_dir/uv-$uv_version-LICENSE-APACHE"
mit_license="$download_dir/uv-$uv_version-LICENSE-MIT"
if [[ -z "$work_root" || "$work_root" == "/" || "$work_root" == "$repository_root" ]]; then
  echo "Refusing to use an unsafe runtime build directory." >&2
  exit 2
fi

mkdir -p "$download_dir" "$work_root" "$(dirname "$output")"
download_verified_runtime_input \
  "https://releases.astral.sh/github/uv/releases/download/$uv_version/uv-aarch64-unknown-linux-musl.tar.gz" \
  "$archive" \
  "$uv_archive_sha256" \
  "uv $uv_version"
download_verified_runtime_input \
  "https://github.com/astral-sh/python-build-standalone/releases/download/$python_release/cpython-$python_version%2B$python_release-aarch64-unknown-linux-gnu-install_only_stripped.tar.gz" \
  "$python_archive" \
  "$python_archive_sha256" \
  "CPython $python_version ARM64 standalone runtime"
download_verified_runtime_input \
  "https://raw.githubusercontent.com/astral-sh/uv/$uv_version/LICENSE-APACHE" \
  "$apache_license" \
  "$apache_license_sha256" \
  "uv Apache license"
download_verified_runtime_input \
  "https://raw.githubusercontent.com/astral-sh/uv/$uv_version/LICENSE-MIT" \
  "$mit_license" \
  "$mit_license_sha256" \
  "uv MIT license"

source_root="$work_root/source-root"
extracted="$work_root/extracted"
python_extracted="$work_root/python-extracted"
rm -rf "$source_root" "$extracted" "$python_extracted"
mkdir -p "$source_root/bin" "$source_root/share/licenses/uv" "$extracted" "$python_extracted"
tar --extract --gzip --file "$archive" --directory "$extracted" --strip-components=1
tar --extract --gzip --file "$python_archive" --directory "$python_extracted"
test -x "$python_extracted/python/bin/python3"
cp -a "$python_extracted/python" "$source_root/python"
install -m 0755 "$extracted/uv" "$source_root/bin/uv"
install -m 0755 "$extracted/uvx" "$source_root/bin/uvx"
for launcher in python python3; do
  printf '%s\n' '#!/bin/sh' 'exec "$(dirname "$0")/../python/bin/python3" "$@"' >"$source_root/bin/$launcher"
  chmod 0755 "$source_root/bin/$launcher"
done
for launcher in pip pip3; do
  printf '%s\n' '#!/bin/sh' 'exec "$(dirname "$0")/../python/bin/python3" -m pip "$@"' >"$source_root/bin/$launcher"
  chmod 0755 "$source_root/bin/$launcher"
done
install -m 0644 "$apache_license" "$source_root/share/licenses/uv/LICENSE-APACHE"
install -m 0644 "$mit_license" "$source_root/share/licenses/uv/LICENSE-MIT"

node "$repository_root/tools/runtime/build-runtime-image.mjs" \
  --pack-id python-uv \
  --version "$pack_version" \
  --source "$source_root" \
  --output "$output" \
  --license "PSF-2.0 AND (Apache-2.0 OR MIT)"

smoke_root="$work_root/image-smoke"
rm -rf "$smoke_root"
unsquashfs -no-progress -d "$smoke_root" "$output" >/dev/null
test -x "$smoke_root/bin/python3"
test -x "$smoke_root/bin/uv"
test -x "$smoke_root/python/bin/python3.13"
test "$(realpath "$smoke_root/python/bin/python3")" = "$smoke_root/python/bin/python3.13"
rm -rf "$smoke_root"
