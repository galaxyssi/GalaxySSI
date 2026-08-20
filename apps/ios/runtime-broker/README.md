# SignalASI iOS Jailbreak Runtime Broker

This optional device-side service connects the iOS app's local runtime client to a Linux environment already provisioned on a jailbroken device. It serves only `127.0.0.1`, requires a per-device Base64 HMAC key, rejects stale and replayed requests, and creates one restricted workspace per SignalASI conversation workspace id.

It is deliberately not a Darwin-shell fallback. The configuration must contain a non-empty `linux_command_prefix` such as a rootless PROot or chroot launcher. If its health command cannot start Linux, the iOS app reports the backend as unavailable.

## What this does and does not reuse

The Android `android-runtime-v1` release catalog supplies signed `.sarpack` metadata and archives. Android executes those images through an Android/Termux-built QEMU engine and a guest broker. That engine is not an iOS executable, so this service does not attempt to launch an Android QEMU pack on iOS.

The iOS app still verifies its signed pack catalog and requires `linux-base` `1.3.9` or newer before it enables execution. The jailbroken device must separately provide an arm64 Linux rootfs and a Linux launcher compatible with the example command prefix. The broker only reports `backend_ready: true` after that launcher passes the configured health command.

## Deploy on a jailbroken device

1. Provision an arm64 Linux rootfs and a rootless launcher such as PROot. The path and flags are device-specific.
2. Copy `signalasi_runtime_broker.py` and a private configuration file to an owner-only directory on the device. Do not use the example file as-is.
3. Generate a pairing key with at least 32 random bytes and Base64 encode it. Put it in `session_key_b64`; enter the identical value in SignalASI's **Runtime broker** settings.
4. Set `linux_command_prefix` to an argument vector which mounts `{workspace}` as `/workspace`, then launches commands following the `--` separator. Do not expose this service beyond `127.0.0.1`.
5. Start the service with the jailbreak's Python 3:

```sh
chmod 700 signalasi_runtime_broker.py
chmod 600 signalasi-runtime-broker.json
/var/jb/usr/bin/python3 signalasi_runtime_broker.py \
  --config /var/mobile/Library/SignalASI/signalasi-runtime-broker.json \
  --port 39761
```

6. In the iOS app, recover signed `linux-base` `1.3.9` or newer, enable Runtime broker, enter port `39761` and the pairing key, then run **Check connection**. Set `allow_package_network_refresh` to `true` only when the broker should refresh APT metadata and install or remove Linux packages; package changes refresh the index before modifying a package.

Use the jailbreak's service manager to keep this process alive. The service runs under the account that owns the configured rootfs and workspace directory; it does not elevate permissions or accept network clients.

## Protocol

The app sends one TCP request per connection. A frame is a four-byte big-endian byte length followed by UTF-8 JSON, up to 1 MiB. Request and response JSON use recursively sorted keys and compact separators before HMAC-SHA256 over the object with `mac` omitted. `mac` is Base64 encoded.

Requests contain `protocol_version: 1`, `request_id`, `operation`, `input`, `context`, `timestamp_epoch_ms`, and `mac`. Clock skew is limited to five minutes; request ids are accepted once in the broker's bounded replay window. The broker accepts `status`, `execute`, and Linux package catalog, search, inspection, installation, and removal operations.

Each `execute` call uses the same default limits as Android: 60 seconds wall clock, 45 seconds CPU, 512 MiB address space, 512 MiB workspace storage, 64 processes, 512 KiB returned output, and 256 MiB requested artifacts. The requested timeout may reduce or extend the wall-clock and CPU budget up to 30 minutes, preserving Android's three-quarter CPU-to-wall-clock ratio. The device Python must expose POSIX `RLIMIT_CPU`, `RLIMIT_AS`, `RLIMIT_FSIZE`, and `RLIMIT_NPROC`; otherwise the broker reports `backend_ready: false` and rejects execution rather than pretending isolation is active. Workspace and requested artifact sizes are verified before and after each execution.

The broker rejects `network_enabled: true` rather than silently allowing the jailbroken Linux environment's network. Linux package search and inspection refresh an empty APT index only when `allow_package_network_refresh` is explicitly set to `true` in the device-owned configuration. Package installation and removal require the same switch and refresh metadata before every change.

## Security boundary

This is for a device the owner intentionally jailbroke. It is not suitable for App Store distribution. The app uses loopback-only pairing; this broker independently enforces loopback binding, HMAC authentication, timestamp freshness, replay rejection, owner-only workspace creation, and an explicit Linux launcher. Keep the configuration and pairing key private.
