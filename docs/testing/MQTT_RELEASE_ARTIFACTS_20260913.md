# MQTT Development Artifacts

Code revision: `a36b6b240bd30091ea17008c71cd6ea685f4bf01`.
These are local development artifacts for PR #3045, not full release acceptance.

## Android

- File: `C:/Users/agent/MQTTDiagnostics/20260913-release-a36b6b240/GalaxySSI-1.2.0-1005.apk`
- Size: **421,145,752 bytes**.
- SHA-256: `BCEEB91C2353C95B2FB3A139DA4DB5FCB6A9129077D40B8B22E769CA4D452D12`.
- AAPT: `com.galaxyssi.chat`, **1.2.0 / 1005**, arm64-v8a, min SDK 26,
  target SDK 34. This is the normal debug package, not a Play release.
- `apksigner verify`: valid v2 signature with the Android Debug certificate.
- `:app:assembleDebug :app:compileDebugAndroidTestKotlin`: success in **2m 7s**.
  Embedded runtime validation passed without disabling the runtime requirement.
- 16 KB audit passed for **74 AArch64 libraries**; QNN audit passed for
  **24 libraries / 221.68 MiB uncompressed**.
- All **293 existing lib/assets entries** match the preceding archived full
  runtime APK byte-for-byte. The smaller ZIP size is not evidence of removed
  runtime payloads. This comparison does not prove every runtime works on-device.
- Build log: `build/mqtt-final-artifacts-android-v1.log`.

## Desktop

Directory:
`C:/Users/agent/MQTTDiagnostics/20260913-release-a36b6b240/source/apps/desktop/dist/GalaxySSI Desktop-win-x64`

The unchanged packaging script ran from an archive of the committed source,
outside the live package directory. Electron was copied to this staging tree;
the Python environment and freshly built Signal JVM sidecar were bundled.
No running production package was stopped or replaced.

- Windows resource write/readback passed: FileVersion **1.2.0.0**,
  ProductVersion **1.2.0**, ProductName **GalaxySSI Desktop**.
- Executable SHA-256:
  `03E2CA9823D28DCEDAF7381280CA45438AA2022E0684A6E042C1EA87401FC29D`.
- **291 packaged Python source files** match the committed worktree sources.
- Final `smoke-packaged.js` passed: layout, bundled dependencies, loopback
  backend APIs, paired-QR generation, native status tool, and packaged UI smoke.
- Overview, gateway/status and evolution-settings screenshots were visually
  inspected: nonblank and readable. They use isolated/fixture state, not a
  real phone pairing or live model/task test.
- Logs: `build/mqtt-final-artifacts-desktop-v1.log` and
  `build/mqtt-final-artifacts-desktop-smoke-v3.log`.

## Isolation And Failed Attempts

The first packaged UI readiness check failed. Preserved follow-up logs exposed
missing source-root configuration, then the need for a real Git checkout.
Pointing the isolated process at a separate detached checkout resolved those
task/evolution API errors without changing application code. A subsequent
standard run failed writing a test attachment under an excessively long Windows
temporary path. The final run used the shorter isolated temp root
`C:/Users/agent/MQTTDiagnostics/pkg3`, preserving the same code and checks.

Failed standard logs (`desktop-smoke-v1/v2`) and diagnostic folders
`ui-diagnostic-v1/v2` remain retained under the paths above. The first failure
alone did not establish a startup timing cause. No timing budget was changed.
The final run used separate data/config/workspace/temp roots and disabled external
services; it did not validate public MQTT or real model availability. The
temporary source checkout remains clean. No system long-path or execution-policy
setting was changed. Generic standalone behavior without a configured source
checkout remains a limitation, not a completed feature of this PR.

## Remaining Acceptance

S26U was absent; the connected SM-T575 was not operated. No phone installation
or current-user Desktop deployment occurred. This clears artifact build and
isolated packaged-startup checks only. Fresh device pairing, full attachment UI,
ten real model windows, lifecycle recovery, network/resource/power and complete
performance comparisons remain in the existing acceptance backlog. The goal
and draft PR are not marked complete by these artifacts.
