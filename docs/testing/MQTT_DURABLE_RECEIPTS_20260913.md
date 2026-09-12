# Durable MQTT Receipt Binding

Date: 2026-09-13. Development branch: `feat/automatic-multi-broker-20260912`.
This checkpoint does not complete the original multi-broker specification.

## Integrated Changes

Android and Desktop now persist the expected receive proof with each production
durable outbound message. A network ACK may retire that row only when all of
these match: authenticated current pair, message ID, `RX_STORED`, the explicit
digest algorithm, and immutable Signal ciphertext digest. The pair binding
includes route, both identity fingerprints, and relationship secret. An ACK
from a replaced key, another pair, or an older ciphertext cannot retire the row.

`BROKER_ACKED`, `CHUNK_STORED`, `TASK_ACCEPTED`, and `RUN_FINISHED` are not accepted
as complete-message receive receipts. Unbound old development rows are not
silently accepted. Existing local discard operations remain separate from the
new network-only verification entry point.

The receive proof is recorded in the existing inbox/ciphertext ledger after
authenticated durable acceptance. Android commits it in the same transaction as
Signal ratchet updates, pre-key consumption, and inbox insertion. Completed-body
compaction preserves the receipt proof. Desktop records its proof after its
durable body handoff and before dispatch/ACK. A recovered body with no wire proof
can still resume safe business dispatch; ACK generation waits for a sender retry
that supplies the ciphertext. A receipt never requests an ACK of its own.

Android receipt journal keys include the wire digest, so a repaired Signal
ciphertext cannot accidentally reuse an earlier prepared receipt. Outbox row
deletion checks proof and ownership inside a database transaction. UI message
and contact correlation are taken from that local row, not peer-supplied display
IDs. The visible status maps `RX_STORED` to the existing localized delivered text;
no layout, background, icon, attachment compression, or encryption policy changed.

The Desktop adapter also fixes two subscription edge cases: a full receive
window cannot be assembled from partial SUBACKs on different brokers, and a late
SUBACK cannot restore a topic already removed from desired subscriptions. Empty
receive windows never count as ready.

## Digest Contract

The cross-platform algorithm is `signal-wire-sha256-v1`. It is intentionally not
the existing local JSON envelope digest used for same-ID content-conflict checks.
Those local digests use language-dependent JSON serialization and must not be
compared directly across Android/Python.

SHA-256 starts with UTF-8 `GalaxySSI/SignalWireReceipt/v1` followed by NUL. In order,
present text fields are `scheme`, `from`, `to`, `signal_type`, `type`, `body`,
`protocol`; present integer fields are `message_type`, `messageType`, `device_id`,
`version`. Each field adds ASCII key length, colon, key, `s` or `i`, UTF-8 value
byte length, colon, and the value bytes. Integers are strict positive integers
bounded by 2^53-1 and rendered in decimal. Unknown mutable transport fields and
wall-clock `time` are excluded. Scheme and nonempty endpoints/body are required.

Golden ASCII wire digest:
`d8d7f88a7543d8bd82fc4d7c364283923a15752ba6d1f23af4903d19a544d581`.
Golden Chinese-endpoint wire digest:
`94c78f615ab4f6d1e8120091f1d0e25f57eeb4b2beb94833b1b6507f957f2d3c`.
Both were verified with Python, JVM JSON, and real Android platform JSON.

The modules also define and test authenticated per-attempt metadata and
`link_rx_stored` frame receipts for the next dispatcher integration. These frame
APIs are not yet activated in actual publication/ingress. The current activated
change is the existing Signal `delivery_ack` path with stronger durable proof.
The pool adapters still publish one physical packet per logical compatibility
token; this checkpoint does not claim active races, hedges, or peer-RTT metrics.

## Verification

| Suite | Result | Evidence |
| --- | --- | --- |
| Pure JVM transport/codec tests | 142 passed, 4.049 s | `build/mqtt-receipt-host/tests.log` |
| Normal Android Gradle focused unit tests | 99 passed, 3m build | `build/mqtt-receipt-gradle-v2.log` |
| Desktop regression, isolated data directory | 273 passed, 43.215 s | `build/mqtt-receipt-python-v3.log` |
| S20U isolated instrumentation | 47 passed, 10.088 s | `build/mqtt-receipt-s20u-device-v1.log` |
| Isolated APK/test build | Passed, 3m49s | `build/mqtt-receipt-isolated-build-v1.log` |
| Normal manifest/configuration restore and main compilation | Passed, 2m3s | `build/mqtt-receipt-normal-restore.log` |

The two JVM suites overlap; their counts must not be added as distinct tests.
Desktop coverage includes the actual bridge receive/dispatch handler, real
pair AEAD, durable outbox proof, copied proof rejection, duplicate receipt,
wrong pair/hash/key, late old ciphertext, and failure to persist. Its broker bus
and Signal decrypt adapter are mocked where stated in the tests; this run is not
a fresh live Desktop/JVM-to-phone MQTT acceptance test.

S20U was **SM-G9880**, ADB serial **R5CN319CESA**, Android 13. The 47 cases were:
21 atomic inbox, 6 route-state, 9 outbox database, 8 receipt-journal, and 3
platform-codec/AEAD tests. The actual libsignal JNI test verifies that a failed
transaction rolls back ratchet, consumed pre-key, inbox, and receipt proof, then
successfully accepts the same ciphertext on retry. No public broker packets,
other phone operations, or production app data were involved in this run.

An initial Python test run hit a Windows test-cleanup error because a direct
SQLite connection was not closed; fixed with `contextlib.closing`. The first
broader run also found one obsolete ID-only ACK mock assertion, updated to test
the new verified path. An initial Gradle invocation omitted ANDROID_HOME; the
successful rerun explicitly configured the installed Android SDK. None of those
failed runs is counted as passing verification.

## Device Isolation

Only `com.galaxyssi.chat.mqttverification` and its `.test` package were installed.
The test build uses a plain Application with no launcher, model startup, or
production services. Both packages were removed **after** terminal runner
completion and `OK (47 tests)`. The pre-existing `com.galaxyssi.chat.test` package
was untouched; `com.galaxyssi.chat` was absent before and after. The attached
SM-T575 was not operated.

Retained artifacts, not shipping APKs:

- `build/artifacts/mqtt-receipt-s20u/verification-app.apk`, SHA-256
  `8030CE210047772394073EA256658D35071F3F81F9C2E8F7D5731538F2F88AC8`.
- `build/artifacts/mqtt-receipt-s20u/verification-test.apk`, SHA-256
  `B3AEFD9DF38E744DCE5AC1930A148DA7F28E4F1C1A8F3C7FCDA3BC8E7C32CC1D`.

These build on the unreleased development base 1.1.110 (996); no new product
release/version is claimed. Normal manifests/build configuration were restored
without the isolated init script and normal main compilation passed. The two
isolated APKs were removed from ordinary build output paths only after their
package IDs and hashes matched the retained artifacts, preventing accidental
installation as a shipping build. Full runtime/native APK packaging is still pending.

## Remaining Acceptance

Still required: production cross-platform QR pairing/receipts, authenticated
attempt dispatch and real peer-latency scheduling, delayed hedges/critical races,
durable wire/chunk bitmaps and missing-block resend, all artifact paths, complete
external-side-effect/cancel reconciliation, lifecycle and authorized-broker
fault/load matrices, repeated performance/power evidence, minimal diagnostics,
full APK/runtime packaging, version updates, coordinated installation, and PR.
Receipt/UI crash-window replay should also be exercised end to end rather than
inferred from storage tests. No running Desktop was replaced in this checkpoint.
