import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';
import { validateDefaultEntries } from './android-default-runtime.mjs';

const entry = (packId, dependencies = []) => ({
  pack_id: packId,
  version: packId === 'python-uv' ? '0.12.1' : '1.3.9',
  architecture: 'arm64-v8a',
  archive_sha256: 'a'.repeat(64),
  archive_size_bytes: 1_024,
  installed_size_bytes: 2_048,
  dependencies,
  asset_path: `runtime/bootstrap/${packId}-${packId === 'python-uv' ? '0.12.1' : '1.3.9'}-arm64-v8a.sarpack`,
});

test('default Android runtime requires the content-verified Python and uv pack', () => {
  assert.throws(
    () => validateDefaultEntries([
      entry('linux-base'),
      { ...entry('python-uv', ['linux-base']), version: '0.12.0' },
    ]),
    /python-uv must be 0\.12\.1 or newer/,
  );
});

test('default Android runtime requires the recoverable persistent Linux base', () => {
  assert.throws(
    () => validateDefaultEntries([
      { ...entry('linux-base'), version: '1.3.8' },
      entry('python-uv', ['linux-base']),
    ]),
    /linux-base must be 1\.3\.9 or newer/,
  );
});

test('default Android runtime requires base Linux and Python with uv', () => {
  const entries = [entry('linux-base'), entry('python-uv', ['linux-base'])];
  assert.equal(validateDefaultEntries(entries), entries);
});

test('default Android runtime rejects missing or misordered dependencies', () => {
  assert.throws(() => validateDefaultEntries([entry('linux-base')]), /linux-base and python-uv/);
  assert.throws(() => validateDefaultEntries([
    entry('linux-base', ['python-uv']),
    entry('python-uv', ['linux-base']),
  ]), /linux-base must not depend/);
  assert.throws(() => validateDefaultEntries([
    entry('linux-base'),
    entry('python-uv'),
  ]), /python-uv must depend/);
});

test('runtime launcher leaves fortify configuration to the Buildroot toolchain', () => {
  const makefile = readFileSync(new URL(
    '../../apps/android/runtime/buildroot-external/package/signalasi-runtime-launcher/signalasi-runtime-launcher.mk',
    import.meta.url,
  ), 'utf8');
  assert.doesNotMatch(makefile, /_FORTIFY_SOURCE/);
});

test('default Linux guest includes packet sockets, virtio networking, and firewall support', () => {
  const kernelConfig = readFileSync(new URL(
    '../../apps/android/runtime/buildroot-external/board/signalasi/aarch64/linux.config',
    import.meta.url,
  ), 'utf8');
  for (const option of [
    'CONFIG_PACKET=y',
    'CONFIG_NETDEVICES=y',
    'CONFIG_VIRTIO_NET=y',
    'CONFIG_NETFILTER_XTABLES_LEGACY=y',
    'CONFIG_IP_NF_IPTABLES_LEGACY=y',
    'CONFIG_NF_REJECT_IPV4=y',
    'CONFIG_IP_NF_TARGET_REJECT=y',
  ]) {
    assert.match(kernelConfig, new RegExp(`^${option}$`, 'm'));
  }

  const buildScript = readFileSync(new URL('./build-linux-base.sh', import.meta.url), 'utf8');
  assert.match(buildScript, /kernel_configs=\("\$output_dir"\/build\/linux-\*\/\.config\)/);
  assert.match(buildScript, /grep -Fxq "\$option" "\$kernel_config"/);
});

test('default Linux guest embeds a pinned persistent Debian userspace', () => {
  const buildScript = readFileSync(new URL('./build-linux-base.sh', import.meta.url), 'utf8');
  const postBuild = readFileSync(new URL(
    '../../apps/android/runtime/buildroot-external/board/signalasi/aarch64/post-build.sh',
    import.meta.url,
  ), 'utf8');
  const guest = readFileSync(new URL(
    '../../apps/android/runtime/guest/signalasi_guest_agent.py',
    import.meta.url,
  ), 'utf8');

  assert.match(buildScript, /debian_rootfs_digest="sha256:[a-f0-9]{64}"/);
  assert.match(buildScript, /download_verified_oci_blob/);
  assert.match(postBuild, /debian-13-slim-arm64-rootfs\.tar\.gz/);
  assert.match(guest, /PERSISTENT_USERSPACE_DIGEST = "[a-f0-9]{64}"/);
  assert.match(guest, /chroot/);
  assert.match(guest, /bind_persistent_userspace/);
  assert.match(guest, /install_persistent_runtime_libraries/);
  assert.match(guest, /libstdc\+\+\.so\.6/);
});

test('default Linux guest includes every persistent disk utility', () => {
  const defconfig = readFileSync(new URL(
    '../../apps/android/runtime/buildroot-external/configs/signalasi_aarch64_defconfig',
    import.meta.url,
  ), 'utf8');
  const buildScript = readFileSync(new URL('./build-linux-base.sh', import.meta.url), 'utf8');

  assert.match(defconfig, /^BR2_PACKAGE_E2FSPROGS=y$/m);
  assert.match(defconfig, /^BR2_PACKAGE_E2FSPROGS_RESIZE2FS=y$/m);
  for (const utility of ['blkid', 'e2fsck', 'mke2fs', 'resize2fs']) {
    assert.match(buildScript, new RegExp(`for binary in[\\s\\S]*${utility}`));
  }
});

test('default Linux build verifies shared libraries needed by language packs', () => {
  const defconfig = readFileSync(new URL(
    '../../apps/android/runtime/buildroot-external/configs/signalasi_aarch64_defconfig',
    import.meta.url,
  ), 'utf8');
  const buildScript = readFileSync(new URL('./build-linux-base.sh', import.meta.url), 'utf8');

  assert.match(defconfig, /^BR2_TOOLCHAIN_BUILDROOT_CXX=y$/m);
  assert.match(defconfig, /^BR2_INSTALL_LIBSTDCPP=y$/m);
  assert.match(buildScript, /libstdc\+\+\.so\.6/);
  assert.match(buildScript, /libgcc_s\.so\.1/);
});

test('default Linux build verifies phone development commands', () => {
  const buildScript = readFileSync(new URL('./build-linux-base.sh', import.meta.url), 'utf8');

  for (const command of ['git', 'ssh', 'curl', 'wget', 'zip', 'unzip', 'tar']) {
    assert.match(buildScript, new RegExp(`for binary in[\\s\\S]*${command}`));
  }
});

test('default Linux build preserves full logs without flooding CI output', () => {
  const buildScript = readFileSync(new URL('./build-linux-base.sh', import.meta.url), 'utf8');

  assert.match(buildScript, /build_log="\$work_root\/buildroot\.log"/);
  assert.match(buildScript, />"\$build_log" 2>&1/);
  assert.match(buildScript, /tail -n 300 "\$build_log"/);
});
