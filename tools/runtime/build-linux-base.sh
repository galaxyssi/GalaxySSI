#!/usr/bin/env bash
set -euo pipefail

buildroot_version="2026.05.1"
buildroot_sha256="ae7f706f087b9ae9083a10a587368dfbf53103c28bf81c2d690198dc4090cb58"
debian_rootfs_digest="sha256:1b7200988f192e72703c70486d494e2457935ac9b0f031ac09eb115b01a12d45"
debian_rootfs_sha256="1b7200988f192e72703c70486d494e2457935ac9b0f031ac09eb115b01a12d45"
source_date_epoch="${SOURCE_DATE_EPOCH:-1781395200}"

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repository_root="$(cd "$script_dir/../.." && pwd)"
source "$script_dir/runtime-download.sh"
external_tree="$repository_root/apps/android/runtime/buildroot-external"
work_root="${GALAXYSSI_RUNTIME_BUILD_DIR:-$repository_root/build/runtime/linux-base}"
download_dir="${GALAXYSSI_RUNTIME_DOWNLOAD_DIR:-$repository_root/build/runtime/downloads}"
archive="$download_dir/buildroot-$buildroot_version.tar.xz"
debian_rootfs_archive="$download_dir/debian-13-slim-arm64-rootfs.tar.gz"
source_dir="$work_root/source"
output_dir="$work_root/output"
build_log="$work_root/buildroot.log"
image_output="${1:-$work_root/linux-base.img}"

if [[ "$(uname -s)" != "Linux" ]]; then
  echo "The linux-base image must be built on a Linux filesystem." >&2
  exit 2
fi

for command in curl sha256sum tar make install realpath mv grep find python3; do
  command -v "$command" >/dev/null || {
    echo "Missing build dependency: $command" >&2
    exit 2
  }
done

repository_root="$(realpath -m "$repository_root")"
work_root="$(realpath -m "$work_root")"
download_dir="$(realpath -m "$download_dir")"
image_output="$(realpath -m "$image_output")"
archive="$download_dir/buildroot-$buildroot_version.tar.xz"
debian_rootfs_archive="$download_dir/debian-13-slim-arm64-rootfs.tar.gz"
source_dir="$work_root/source"
output_dir="$work_root/output"
build_log="$work_root/buildroot.log"
if [[ -z "$work_root" || "$work_root" == "/" || "$work_root" == "$repository_root" ]]; then
  echo "Refusing to use an unsafe runtime build directory." >&2
  exit 2
fi
if [[ "$source_dir" != "$work_root/source" || "$output_dir" != "$work_root/output" ]]; then
  echo "Runtime build paths are inconsistent." >&2
  exit 2
fi

mkdir -p "$download_dir" "$work_root" "$(dirname "$image_output")"
download_verified_runtime_input \
  "https://buildroot.org/downloads/buildroot-$buildroot_version.tar.xz" \
  "$archive" \
  "$buildroot_sha256" \
  "Buildroot $buildroot_version"
download_verified_oci_blob \
  "library/debian" \
  "$debian_rootfs_digest" \
  "$debian_rootfs_archive" \
  "$debian_rootfs_sha256" \
  "Debian 13 slim ARM64 root filesystem"

rm -rf "$source_dir" "$output_dir"
mkdir -p "$source_dir" "$output_dir"
tar --extract --xz --file "$archive" --directory "$source_dir" --strip-components=1

export SOURCE_DATE_EPOCH="$source_date_epoch"
export GALAXYSSI_DEBIAN_ROOTFS_ARCHIVE="$debian_rootfs_archive"
export GALAXYSSI_DEBIAN_ROOTFS_SHA256="$debian_rootfs_sha256"
make -C "$source_dir" O="$output_dir" BR2_EXTERNAL="$external_tree" galaxyssi_aarch64_defconfig
echo "Building the GalaxySSI Linux runtime; full Buildroot output is stored at $build_log"
if ! make -C "$source_dir" O="$output_dir" BR2_EXTERNAL="$external_tree" \
  -j"${GALAXYSSI_RUNTIME_BUILD_JOBS:-$(nproc)}" >"$build_log" 2>&1; then
  echo "Buildroot failed. Last 300 log lines:" >&2
  tail -n 300 "$build_log" >&2
  exit 1
fi
echo "Buildroot completed successfully"

shopt -s nullglob
kernel_configs=("$output_dir"/build/linux-*/.config)
shopt -u nullglob
if (( ${#kernel_configs[@]} != 1 )); then
  echo "Expected exactly one final Linux kernel configuration; found ${#kernel_configs[@]}" >&2
  exit 3
fi
kernel_config="${kernel_configs[0]}"
for option in \
  CONFIG_EXT4_FS=y \
  CONFIG_PACKET=y \
  CONFIG_NETDEVICES=y \
  CONFIG_VIRTIO_NET=y \
  CONFIG_NETFILTER_XTABLES_LEGACY=y \
  CONFIG_IP_NF_IPTABLES_LEGACY=y \
  CONFIG_NF_REJECT_IPV4=y \
  CONFIG_IP_NF_TARGET_REJECT=y; do
  if ! grep -Fxq "$option" "$kernel_config"; then
    echo "Required runtime kernel option is missing from the final kernel: $option" >&2
    exit 3
  fi
done

for binary in blkid e2fsck mke2fs resize2fs; do
  if ! find "$output_dir/target" -type f -name "$binary" -perm /111 -print -quit | grep -q .; then
    echo "Required persistent system disk utility is missing: $binary" >&2
    exit 3
  fi
done

for binary in git ssh curl wget zip unzip tar; do
  if ! find "$output_dir/target" -type f -name "$binary" -perm /111 -print -quit | grep -q .; then
    echo "Required phone development command is missing: $binary" >&2
    exit 3
  fi
done

for library in libstdc++.so.6 libgcc_s.so.1; do
  if ! find "$output_dir/target" \( -type f -o -type l \) \
      -name "$library" -print -quit 2>/dev/null | grep -q .; then
    echo "Required persistent userspace runtime library is missing: $library" >&2
    exit 3
  fi
done

install -m 0644 "$output_dir/images/Image" "$image_output"
sha256sum "$image_output"
