# Multi-Broker Coordinated Deployment

Date: 2026-09-13. Branch: `feat/automatic-multi-broker-20260912`.
Merged main through `6e303ed06` in merge commit `ff313c1e2`.
This is installation/startup evidence, not full P0-P3 acceptance.

## Full Android Package

- Target: S20U SM-G9880, Android 13, serial `R5CN319CESA` only.
- Package: `com.galaxyssi.chat`, version 1.1.113, code 999.
- APK: `apps/android/app/build/outputs/apk/debug/app-debug.apk`.
- Size: 418717254 bytes.
- SHA-256: `2212E1596FAC75E615F4F81F06FA99C7436972EC2AEF26A3EB7513572B9DA622`.
- Full `:app:assembleDebug` passed in 2m 24s, 70 tasks. No native/runtime
  exclusion flags were used. Log: `build/mqtt-full-app-v3.log`.
- Verified embedded runtime manifest and APK entries for Linux 1.3.9,
  Python/uv 0.12.1, QEMU, Tiny ASR and native memory/llama libraries.
- Restored the pinned llama source submodule, not a model download, to build
  the native library. Earlier attempts exposed missing Rust setup and the
  uninitialized submodule; both prerequisites were supplied, not omitted.
- Production package was absent before installation. `adb install -r`
  succeeded; package-manager version verification matched the built APK.
- Cold activity launch returned OK, TotalTime 699ms / WaitTime 710ms. This
  measures Android launch reporting, not complete model/runtime readiness.
- Main UI was visible and the notification prompt was accepted. Device crash
  log had no entries at the final check. Screenshot:
  `build/mqtt-s20u-ready-v1.png`.
- No operations on connected SM-T575 or on S26U during this deployment.

## Desktop Package And Startup

- Packaged Desktop 1.1.50, with Python dependencies and built Signal sidecar.
- Runtime venv outside the repository:
  `C:/Users/agent/MQTTDiagnostics/20260913-desktop-runtime`.
- Package: `apps/desktop/dist/GalaxySSI Desktop-win-x64/`.
- Final packaging log: `build/mqtt-desktop-package-v3.log`.
- Final packaged `link_delivery.py` SHA-256 matches source:
  `6CD4AF60C2B40881D8F9A3344CBADCAF9299F9ED3DE6CA17E7694B2559CACD4C`.
- Packaged smoke before the delivery-schema follow-up passed dependency,
  isolated backend and UI checks: `build/mqtt-desktop-packaged-smoke-v1.log`.
  The schema follow-up was then repackaged and checked in the real runtime.
- Real health endpoint reported Signal sidecar ready, automatic selection,
  TLS enabled, and EMQX/HiveMQ/Mosquitto connected with no pending subscriptions.
  Opening the QR added its pairing subscription to each path.
- No paired peer existed at the final pre-scan check: `receive_ready=true`
  but overall business `ready=false` is expected, not proof of a completed link.
- The production window initially remained visually blank despite initialized
  DOM/backend. A diagnostic restart and software-rendered launch did not alone
  resolve the blank view; maximizing the window triggered a successful repaint.
  The current process uses `--disable-gpu` and displays the full pairing QR.
  This is a host launch workaround, not a permanent startup-rendering fix.
- The temporary localhost renderer-debugging listener was removed on restart.
  No privacy/security switches, TLS checks, pairing grants or user history were
  changed to make startup pass. Desktop executor permission remains unchecked.

## Local Delivery Ledger Fix

Real startup exposed `no such column: dispatch_retry_at` when an existing local
ledger had the earlier inbound table schema. Connecting to the brokers did not
make this failing dispatch initialization safe to ignore.

The initializer now adds missing dispatch columns under a writer transaction,
rechecking after acquisition to handle concurrent openers. Historical ACK-only
rows are preserved but marked `uncertain`; they cannot become fresh work and
repeat unknown side effects. Existing dispatch proof is retained. New receives
keep the `stored` default. This only opens the local database safely; it does
not introduce old wire-protocol compatibility.

A consistent SQLite backup was made outside the project before replacement:
`C:/Users/agent/MQTTDiagnostics/20260913-deploy-backup/galaxyssi_link_delivery-before-schema.db`.
Read-only inspection of the running database confirmed all seven dispatch
columns and the pending index. The existing inbound row count was zero.

## Verification

| Scope | Result | Evidence |
| --- | --- | --- |
| Backend regression in release dependency venv before schema follow-up | 228 passed, 33.569s | `build/mqtt-packaged-env-regression-v1.log` |
| Schema, delivery, batching, stored dispatch, actual bridge regression | 53 passed, 4.770s | `build/mqtt-deploy-regression-v1.log` |
| Desktop checks | 34 tests passed; structure check passed | `build/mqtt-desktop-check-v4.log` |
| Full Android build and S20U install | Passed | Full-build log and package verification above |
| Final Desktop startup | Three paths subscribed, Signal ready, QR visible | Real `/health` and native UI inspection |

Counts overlap previous checkpoints. The 53-case run uses isolated data/state
paths and controlled transport fixtures, not 53 public-network deliveries.
Static encryption checks were updated to follow the actual encrypted database
classes instead of requiring the superseded store implementation strings.

## Pending Acceptance

User scan and native Signal/complete durable business delivery are next. Real
message uniqueness, image/file/video hashes and preview/open/save, owned-broker
outage/loss/performance matrices, App/App, ten windows, Doze/reboot and measured
power remain pending. No large traffic or fault injection ran against public
brokers. The full goal is still active; no PR or complete-feature claim yet.
