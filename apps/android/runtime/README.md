# Android On-Device Runtime Sources

This directory contains source and reproducible build definitions for the GalaxySSI Linux Guest.
It does not contain release binaries, private signing keys, downloaded toolchains, or user data.

- `guest/` implements the authenticated Guest broker.
- `buildroot-external/` defines the AArch64 Linux base image and native task launcher.
- `qemu/` defines the minimal QEMU 10.2.1 Android cross-build and redistribution notice. The
  Termux package builder is a pinned build-time framework only; the app does not require Termux.
- Toolchain images use a fixed read-only ABI: self-contained executable wrappers live in `bin/`,
  the image includes `galaxyssi-pack.json`, and every declared capability has a required entrypoint.
- Runtime images are built under ignored `build/` paths, signed as `.sarpack` release artifacts,
  and installed by the Android runtime-pack manager.

Required entrypoints are:

| Pack | Entrypoints |
| --- | --- |
| `python-uv` | `bin/python3`, `bin/uv` |
| `node-js` | `bin/node`, `bin/tsx` |
| `go` | `bin/go` |
| `rust` | `bin/rustc` |
| `cpp` | `bin/cc`, `bin/c++` |
| `java` | `bin/java`, `bin/javac` |
| `gradle` | `bin/gradle` |
| `browser-automation` | `bin/galaxyssi-browser`, `bin/playwright` |
| `ffmpeg` | `bin/ffmpeg`, `bin/ffprobe` |

Pinned builders cover `python-uv`, `node-js`, `go`, `rust`, `cpp`, `java`, `gradle`, browser automation, and
`ffmpeg`; run the
matching `npm run runtime:build-*` command on Linux to produce an unsigned image and signing
config. These source recipes do not mean the binary packs have been published or installed.

Entrypoints must be relocatable files or wrappers whose dependencies remain inside the signed pack
or the matching `linux-base`. Absolute symlinks, setuid/setgid files, world-writable files, device
nodes, and escaping symlinks are rejected by the image builder.

The `linux-base` image intentionally includes a bounded non-interactive Agent toolbox:

- shell and text processing: Bash, findutils, grep, sed, gawk, diffutils, patch, less, file, and tree;
- archive and compression: tar, gzip, bzip2, xz, zstd, cpio, zip, and unzip;
- structured data and transport: jq, curl, wget, CA certificates, and OpenSSL command-line tools;
- project and local data work: Git, SQLite, nano, and Vim;
- secure transport: OpenSSH client, server, SFTP, and key utilities, with the server disabled by default;
- process and filesystem inspection: procps-ng and the selected util-linux binaries.

Compilers, browser automation, and media toolchains remain signed, independently updateable
runtime packs. The browser pack contains pinned Playwright and headless Chromium builds, depends
on the Node.js pack, and is never downloaded without an explicit user install action. Guest
networking remains disabled unless a task receives an explicit domain allowlist; bundling network
clients does not grant network access. The image never starts sshd automatically and contains no
pre-generated host key or password credential.

The standard Android APK bundles the native QEMU engine plus signed `linux-base` and `python-uv`
archives. On first launch, the app verifies and installs both default packs into private storage.
It must not report the runtime as ready unless the engine, verified base image, Python/uv pack, and
authenticated Guest health handshake are all present. Other language and media packs remain
independently downloadable. The `python-uv` 0.12.1 pack contains pinned ARM64 CPython 3.13.15 and
uv 0.11.29 runtimes, so Python execution and dependency management do not depend on packages
already being installed inside the persistent Debian system. Pack 0.12.1 also records a content
fingerprint, preventing a stale same-version installation from being reused after its contents
change.

The optional `android-sdk` pack combines the official Android 36 platform and Java build tools
with native ARM64 `aapt`, `aapt2`, `aidl`, and `zipalign` executables built from pinned AOSP sources.
It depends on the Java pack, exposes a Gradle AAPT2 override inside the Guest, and is not embedded in
the APK. Users install it from the signed software catalog when a phone-local Android build needs it.

`linux-base` 1.3.9 gives the authenticated Android host a root execution principal with direct guest filesystem and network access. It provisions a private 30 GiB sparse ext4 system disk and deploys a digest-pinned Debian 13 ARM64 userspace into it. Shell work runs in that persistent system, so apt/dpkg changes survive restarts, while existing signed language packs remain available without regression. Read-only Buildroot development tools are exposed inside the persistent userspace through loader-safe wrappers, including the complete Git helper path and host trust store, so Git, SSH, curl, and wget are ready before a project clone without a first-run package download. The system disk is checked before each mount, and the Android host can isolate and rebuild a damaged userspace without discarding project workspaces. Runtime driver sources live in an excluded control directory, so executing Agent commands cannot overwrite or pollute project entrypoints. The build verifies the required filesystem tools, virtio network driver, packet socket support used by DHCP, direct guest DNS fallback, and a writable persistent task cache before package managers start. Restricted launcher and firewall support remain available for explicit restricted runtimes, and the final kernel still verifies the complete legacy reject path.
and visible bootstrap failures while retaining negotiated
`runtime.secret_environment` support. Hosts send MCP and
tool credentials only when the Guest advertises that capability; an older Guest remains usable for
non-secret work but is rejected explicitly for secure environment injection instead of silently
running without the requested credential.

Build the native engine on Linux with Docker, `dpkg-deb`, `patchelf`, and LLVM tools:

```bash
npm run runtime:build-android-qemu
```

The command verifies the pinned package-builder archive, builds QEMU and its dependency graph from
source for Android ARM64, follows the exact ELF dependency closure, and emits ignored generated JNI
and notice directories under `build/runtime`. Gradle consumes those directories when present. A
source recipe without those generated files does not add a placeholder engine to the APK.
