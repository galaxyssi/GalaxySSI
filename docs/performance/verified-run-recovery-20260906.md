# Verified Run recovery verification, 2026-09-06

Base: main `6e5da5157`, including merged PR #2815. Android 1.0.12 (858),
Desktop source/package 1.0.8. iOS is unchanged. The user's current test device
is S20U, not the S26U named in the original roadmap.

## Completed checks

- Android JVM: 36 passed, zero failures/errors across recovery client (7),
  recovery coordinator (15), task identity (5), control-plane executor (9).
- Isolated Desktop Run Kernel regression: 118 passed, including 12 new recovery
  query tests with identity, status and malformed-payload subcases. Temporary
  HOME/USERPROFILE/APPDATA/state prevented access to the running Desktop store.
- Additional isolated MQTT task-routing regressions: 23 passed.
- Repository `npm run check`: passed. This includes read-only iOS structure
  validation, not iOS implementation changes or device testing.
- Android APK and instrumentation APK: built successfully. Existing compiler
  deprecation/native path warnings remain; no build errors.
- Desktop portable package built successfully. The packaged recovery handler
  SHA-256 matches source. This package uses the installed Python runtime, and
  rcedit was unavailable, so executable file resources retain Electron defaults.

## S20U evidence

Device: Samsung S20 Ultra, SM-G9880. No S26U or SM-T575 operations were performed.
Pre-install available memory was 5,889,028 KiB. Existing Android 1.0.11 (857)
was upgraded in place; the existing first-install timestamp was preserved.

Eight instrumented tests were reported: **7 passed, 1 skipped, 0 failed**.
Three new tests validate encrypted ledger cancellation protection, stale-progress
protection, and reopen/idempotency. Four existing real-socket/cloud cancellation
regressions also passed. The one skipped test is the explicit live Desktop query.
The temporary test package was removed afterward; production App data was not.

Activity launch measurements: one warm launch 650 ms, cold launches 1,896 ms
and 1,900 ms (the latter after the final concurrency fix and reinstallation).
These are Activity timings, not complete task recovery timings or P95/P99 values.
After cold launch, the existing conversation and previous answer remained visible.
The crash buffer was empty. No new provider response latency was measured here.

Installed final APK size: 417,826,748 bytes. SHA-256:

`737D69A8324A2DE3ECE0842BF574B7DD92C5401CF740ACF76C21BEB89DB9E1C1`

Local evidence files under `build/`:

- `verified-recovery-race-build.log`
- `verified-recovery-probe-build.log`
- `verified-recovery-backend-tests.log`
- `verified-recovery-final-repo-check.log`
- `verified-recovery-mqtt-routing-tests.log`
- `verified-recovery-s20-final-device-tests.log`
- `verified-recovery-s20.png`
- `galaxyssi-verified-recovery-final-1.0.12.apk`
- `galaxyssi-verified-recovery-final-tests.apk`

## Pending live acceptance

Desktop deployment was blocked by execution policy before process creation.
No old process was stopped, no new Desktop was started, and no pairing data was
changed. The existing task-recovery Desktop 1.0.4 remained running (PID 21368).
No alternate execution path was used to bypass the rejection.

The 1.0.8 package is at
`apps/desktop/dist/GalaxySSI Desktop-win-x64/GalaxySSI Desktop.exe` in this worktree.
After the user starts it, reinstall the test APK and invoke
`AgentRemoteRecoveryDeviceTest` with `live_recovery_probe=true` on S20U.
That test connects through the normal MQTT bootstrap and queries an existing
paired task without creating or re-executing it.

The PR remains draft until real paired status recovery is verified. Final-answer
redelivery, complete UI reattachment and five-second end-to-end recovery remain
separate work; this phase does not claim those roadmap items complete.
