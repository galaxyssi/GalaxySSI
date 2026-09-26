#!/usr/bin/env sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
runtime_dir=$(CDPATH= cd -- "$script_dir/../../../.." && pwd)

install -D -m 0755 \
  "$runtime_dir/guest/galaxyssi_guest_agent.py" \
  "$TARGET_DIR/usr/libexec/galaxyssi_guest_agent.py"
install -D -m 0644 \
  "$runtime_dir/guest/galaxyssi_network_proxy.py" \
  "$TARGET_DIR/usr/libexec/galaxyssi_network_proxy.py"

test -f "${GALAXYSSI_DEBIAN_ROOTFS_ARCHIVE:?Debian root filesystem archive is required}"
install -D -m 0644 \
  "$GALAXYSSI_DEBIAN_ROOTFS_ARCHIVE" \
  "$TARGET_DIR/usr/share/galaxyssi/debian-13-slim-arm64-rootfs.tar.gz"
printf '%s\n' "${GALAXYSSI_DEBIAN_ROOTFS_SHA256:?Debian root filesystem digest is required}" \
  >"$TARGET_DIR/usr/share/galaxyssi/debian-13-slim-arm64-rootfs.sha256"

rm -rf "$TARGET_DIR/usr/libexec/__pycache__"

# Ship SSH tooling without exposing a listening service by default. GalaxySSI may start sshd only
# after an explicit user action provisions host keys and a key-only authentication policy.
rm -f "$TARGET_DIR/etc/init.d/S50sshd"
rm -f "$TARGET_DIR/etc/ssh/ssh_host_"*
