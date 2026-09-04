# GalaxySSI iOS Offline Runtime

Full offline IPA builds add the GalaxySSI Linux 1.3.9 ARM64 kernel image to this resource folder. The image contains the pinned Debian 13 baseline and guest Agent service. At first start, the app copies it to its private Application Support directory and provisions a sparse persistent Debian system disk there.

The IPA also embeds the fixed UTM SE 4.7.5 no-JIT QEMU frameworks. QEMU runs in the app process and the host/guest Agent protocol uses a private Unix socket. No jailbreak launcher, external root filesystem, or separately installed UTM app is required.

The offline bundle also includes the same verified ARM64 Node.js 24.18.0 SquashFS runtime pack used by Android. QEMU attaches it as a read-only virtio disk, the guest validates its descriptor and capabilities, and `/opt/galaxyssi/packs/node-js/bin` precedes the Debian system path for Agent commands.
