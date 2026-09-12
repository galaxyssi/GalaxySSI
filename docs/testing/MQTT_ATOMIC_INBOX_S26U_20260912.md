# Android Atomic MQTT Inbox: S26U Verification

Date: 2026-09-12. Branch: `feat/automatic-multi-broker-20260912`.
Base checkpoint: `0600383d0`; the atomic-inbox changes were uncommitted when tested.

## Scope and Isolation

- User-designated device: S26U, model `SM-S9480`, Android 16 / API 36.
- Production `com.galaxyssi.chat` was absent before this verification. The existing
  `com.galaxyssi.chat.test` package was not altered or removed.
- Built production Kotlin/dependencies with the explicit
  `tools/dev/mqtt-isolated/isolated.init.gradle` profile. The target was the separate
  `com.galaxyssi.chat.mqttverification` package, with a plain Android Application,
  no launcher or application components, and no model/runtime assets or CMake
  runtime libraries. The dependency's real libsignal JNI library was retained.
- This profile did not start GalaxySSI services, MQTT connections, UI, or models.
  All Keystore keys, Signal records, and test databases belonged to the isolated
  Android UID. No public broker traffic, real conversations, or real pairing keys
  were used. SM-T575 and S20U were not operated.

## Results

| Suite | Passed | Failed |
| --- | ---: | ---: |
| `MqttAtomicInboxDeviceTest` | 17 | 0 |
| `MqttRouteStateDeviceTest` | 6 | 0 |
| `SecuritySensitiveStateInstrumentedTest` | 6 | 0 |
| Total | 29 | 0 |

AndroidJUnitRunner reported `OK (29 tests)` and 1.647 seconds of test execution.
That is suite duration, not a message latency, network benchmark, or p95.

Verified on real Android SQLite/Keystore/libsignal:

- WAL and `synchronous=FULL` on the transport store's write connection.
- Body plus immutable-content/ciphertext bindings visible to an independent
  SQLite connection after commit, with the body encrypted at rest.
- Post-insertion exceptions roll back body, ratchet-record write, usage counters,
  and replay bindings. A failed attempt does not evict previously accepted work.
- An actual libsignal pre-key decrypt, session creation, pre-key consumption, and
  inbox insertion roll back together. Retrying the same ciphertext then succeeds.
- Thirty concurrent acceptance attempts produce one stored record and 29 pending
  duplicates, not thirty logical messages.
- Conflicting content is rejected without replacing accepted content. Identical
  message/cipher IDs in separate pairing scopes remain independent.
- Completion retains a replay tombstone but removes the stored payload. ID-only
  completion cannot finish another record. A missing body cannot produce a stored
  replay receipt.
- Global/per-pair quotas, transactional quota rollback, bounded alternate cipher
  bindings, paged replay, scoped revocation, and retention of pending work.
- Persisted route epochs, concurrent window epoch increments, stale/conflicting
  route rejection, expiration watermarks, and isolated route revocation.
- Signal/pre-key rotation, encrypted identity/trust storage, QR signature checking,
  and one-time phone pairing/control replay protection.

## Reproduction and Artifacts

Build instructions: `tools/dev/mqtt-isolated/README.md`.
Instrumentation classes were selected explicitly; the full unrelated device test
suite was not run. In addition to the two classes in that README, this run selected
`com.galaxyssi.chat.SecuritySensitiveStateInstrumentedTest` in the isolated package.

- Build log: `build/mqtt-isolated-package-final.log`, successful in 13m 9s.
- Device output: `build/mqtt-s26u-storage-verification.log`.
- Target APK: 186,128,005 bytes; SHA-256
  `F9659F1417F711254591FC514734517030F46D6DE0ABCB721101D4FC3E04DB7F`.
- Instrumentation APK SHA-256:
  `5968C14B1FBFC24BFC76FA5A000FF7F7E675E43169857E80E3D5CDF06094FE58`.
- Both verification packages were successfully uninstalled after the run. The
  pre-existing test package remained, and no production app was installed.

The first isolated build exposed an unwanted llama-runtime CMake dependency; the
explicit test profile now omits both app and llama native builds. An overlapping
retry hit Windows' R.jar file lock; that failed run was not used as evidence. The
reported APK came from the subsequent completed build with no concurrent build
in this worktree.

## Not Proven By This Run

This verifies the Android receive-storage primitives and their real Signal
transaction, not a finished three-broker product. It did not exercise a physical
process kill during the transaction, a device reboot, power loss, MQTT receipt
loss, the full UI/Run Kernel handoff, cross-broker attachments, or a live Desktop
Signal sidecar. Repository recreation is not a process-restart test.

Actual lifecycle activation on both endpoints, authenticated content/scope-bound
receipts, durable fragment recovery, side-effect reconciliation, pairing/resume,
and the full private-broker/device/performance/power matrix remain required. The
isolated APK must not be shipped or treated as the final Android installation.
