# Durable MQTT Wire Fragments: Android and Desktop

Date: 2026-09-13. Development checkpoint, not a full multi-broker release.

## Actual Integration

Android's phone-contact and Desktop-contact receive paths now use
`AndroidMqttChunks` / `MqttDurableChunks`. Desktop's actual bridge uses
`DurableChunkAssembler`. All calls occur after existing pair authentication and
endpoint validation. Storage scope includes the configured pair, fingerprints,
and pairing key, rather than the arrival broker or rotating receive Topic.

Previously Android included the Topic in its in-memory assembly key. Parts on
successive aliases could therefore enter separate assemblies. Both endpoints
also lost partial assemblies when transport state was cleared. The new receive
paths preserve partial bytes across disconnects and process restarts.

The existing Link/Signal SQLite database owns the fragment tables. Stored bytes
are already Signal ciphertext; no new attachment-at-rest AES, task ledger,
per-contact thread, or plaintext attachment copy is introduced. Production
storage uses WAL and FULL synchronous commits.

Before reserving capacity, each fragment must pass strict counter, endpoint,
canonical Base64, size, and SHA-256 checks. A domain-separated manifest digest
binds full-wire hash, count, total size, source, and destination. Unique database
keys prevent concurrent copies from creating duplicate parts or quota charges.
Different metadata or valid-but-conflicting bytes cannot replace accepted data.
Known-hash bytes corrupted in storage can be repaired by a verified matching
retransmission. Full-wire hash, strict UTF-8, endpoints, and Signal wire digest
are checked before handing the reconstructed wire to existing Signal ingress.

The store reserves declared total size, with global limits of 16 transfers /
32 MiB and per-pair limits of eight transfers / 16 MiB. Overflow does not evict
accepted incomplete transfers. Retention is eight days from initial acceptance,
not refreshed by duplicates. Existing wire geometry is unchanged: at most
380 KiB data per wire fragment, 2 MiB reconstructed wire, and 96 fragments.
These wire bounds are not the maximum application attachment size.

Complete fragments are released only after the original business inbox supplies
a committed, matching Signal-wire receipt. If that handoff fails, completed
bytes remain available; retransmitting one part can retry the handoff without
re-uploading the entire wire. Business task/side-effect semantics are unchanged.

## Executed Tests

- Desktop: 60 tests passed in 16.093 seconds. Command from the backend directory:
  `python -m unittest test_mqtt_durable_chunks test_mqtt_durable_chunk_bridge test_mqtt_chunk_process_recovery test_mqtt_wire_chunking test_mqtt_delivery_bridge test_mqtt_stored_dispatch -v`.
  Both state environment variables pointed to an isolated ignored build path.
  Log: `build/mqtt-durable-chunks-python-v4.log`.
- Expanded Desktop regression: 165 tests passed in 13.392s, including the 60
  above, pool/policy/route/ingress, diagnostics, and phone-tool routing. Log:
  `build/mqtt-durable-chunks-python-regression-v2.log`. The first expanded run
  found a test-only cold SQLite initialization race and an older diagnostic
  fixture that mocked away the required wire-receipt write. The chunk fixture
  now uses the actual Link connection factory; the diagnostic fixture wraps the
  real ciphertext binding. No production receipt check was weakened. The cold
  concurrent-fragment case also passed ten successive runs with fresh databases;
  these are repeats of one case, not ten new distinct tests. Log:
  `build/mqtt-durable-chunks-python-concurrent-v1.log`.
- Thirteen storage tests use real SQLite. Three additional actual-bridge tests
  exercise pair AEAD, disconnect/Topic rotation, delayed inbox handoff, replay,
  and corrupted input. Their Signal JNI interaction is a durable fixture, not
  a claim of native cross-device delivery.
- Two subprocess tests call `os._exit` immediately before or after the actual
  fragment commit. Uncommitted data is not claimed; committed data survives and
  completes by transmitting only the remaining fragment. This is process-exit
  recovery, not a physical power-loss test.
- Android isolated build passed in 3m 51s; a subsequent test-only adjustment to
  assert WAL/FULL settings rebuilt successfully in 51s. Production Kotlin and
  real libsignal dependencies are compiled, but embedded runtime/native build
  packaging is disabled for these non-launchable test packages.
- S20U, SM-G9880, Android 13, serial `R5CN319CESA`: 68 tests passed in 12.647s.
  Thirteen new fragment cases plus 55 existing atomic Signal/inbox, route,
  outbox, receipt, frame, and hedge tests. These are not 68 full MQTT tasks.
  Log: `build/mqtt-durable-chunks-s20u-device-v1.log`.
- Separate S20U process recovery passed: the prepare invocation saved part zero
  in PID 22624. After force-stop of only the disposable test package and a
  no-PID check, the verify invocation in PID 22665 recovered part zero, accepted
  only part one, validated the result, and released it using a wire proof.
  Logs: `build/mqtt-chunk-process-s20u-prepare-v1.log` and
  `build/mqtt-chunk-process-s20u-verify-v1.log`. This is one two-phase scenario,
  not two distinct recovery scenarios or a complete MQTT restart test.
- Kotlin source-size policy passed with the existing 153600-byte default.
- Normal Android Gradle configuration was restored and passed 87 focused unit
  tests with zero failures, errors, or skips in 3m 25s. Counts: Link protocol 35,
  wire chunking 10, delivery dispatch 18, peer routes 20, traffic policy four.
  Log: `build/mqtt-durable-chunks-normal-test-v1.log`. This compiled the actual
  main Kotlin again, excluding native memory generation and full embedded
  runtime packaging; it did not produce a shipping APK.

S20U was the only operated device. `com.galaxyssi.chat.mqttverification` and its
runner were installed, tested, and removed. The pre-existing
`com.galaxyssi.chat.test` package remains untouched. No production App install,
data reset, pairing scan, or running Desktop replacement occurred.
The isolated APK files in ordinary Gradle output locations were removed after
package/hash verification, to avoid confusing them with a shipping build. The
explicit artifact copies below remain. Their inherited base version is
1.1.110 (996), not a new Android/Desktop release version.

Retained non-shipping artifacts are under
`build/artifacts/mqtt-durable-chunks-s20u/`:

| Artifact | SHA-256 |
| --- | --- |
| `verification-app.apk` | `06244F476D2A29B8D848F5DDC2F06C65EC93F25ED6F6B2038B95EAAEF7FCC0AA` |
| `verification-test.apk` | `19FEFC5EB973B138ACC05AA268E27C2165038486D10BC1D6B1FDE570917B83FD` |

## Remaining Before P2 Acceptance

This checkpoint does not yet send authenticated `CHUNK_STORED` bitmaps or
persist outbound per-fragment acknowledgement state. Adaptive cross-broker
striping, missing-only retry, final durable proof/probe behavior, and recovery
cleanup if a process exits between inbox commit and fragment release still
need integration. Existing application attachment manifests and Blob transfers
must continue to own artifact identity and final preview/open/save behavior.

Pending work also includes revocation cleanup, coordinated sender/receiver quota
and expiry handling, owned-broker fault/load matrices, actual native App/Desktop
and App/App pairing acceptance, ten-window lifecycle, performance/power evidence,
version updates, full-runtime APK packaging, coordinated installation, and PR.
No public broker was load-tested by the tests in this checkpoint.
