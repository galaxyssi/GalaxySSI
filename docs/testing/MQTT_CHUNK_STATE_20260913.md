# Authenticated MQTT Fragment State and Missing-Only Recovery

Date: 2026-09-13. Development checkpoint, not complete P2/P3 acceptance.

## Runtime Changes

Android and Desktop now connect the actual durable fragment publishers and
authenticated ingress to the version-1 chunk-state exchange. This is not only
a codec or test-only transport. Existing durable message IDs, Signal wire,
outbox retry loops, physical budgets, inbox proof and application handlers remain
the owners of business delivery and execution.

The sender persists a solicited query nonce, receiver bitmap/epoch/revision and
per-index attempted brokers. Retries select only absent bits and prefer an
untried healthy common path under the existing scheduler. Once all bits are
known stored, a small query replaces the full wire upload. Stored chunks and
path/bitmap metadata survive process restart; a new query prevents delayed state
from a previous round or pair/key from overwriting current state.

The receiver reports only verified durable fragments. A newer revision may
retract corrupt stored bytes. Unknown probes allocate no fragment space.
Complete wire waiting for an interrupted Signal handoff can be recovered from
local stored bytes. After matching business-inbox proof, only a compact
completion proof remains. A probe or duplicate can repeat the original business
receipt only while the current inbox still supplies the matching wire proof.
It does not invoke Signal decryption or a task again for completed data.

Sender metadata retains the existing seven-day retry horizon. Receiver pending
bytes/proofs use fixed eight-day retention. Both count-bounded metadata stores
also enforce target expiry independently of their bounded 256-row background
cleanup, so a cleanup backlog cannot revive a stale transfer. Android retains
the existing fragment-error diagnostic accounting without logging payloads.

See [protocol](../protocol/MQTT_MULTIPATH.md#wire-fragment-state-exchange) for exact
query, bitmap, scope and confirmation semantics. No new attachment-local AES,
chat UI, per-contact permanent thread, model/task identity, or whole-file
duplicate queue was added.

## Verification

- JVM: 178 tests passed in 5.539s, including six new pure codec cases and the
  Android/Python UTF-8 manifest and bitmap golden. Log:
  `build/mqtt-chunk-state-host-v2/tests.log`.
- Initial expanded Desktop run: 121 tests passed in 25.690s, including five
  actual bridge/publisher integration cases and 13 outgoing-state/storage cases.
  Log: `build/mqtt-chunk-state-python-v3.log`. This predates the additional
  bounded-expiry test and fix.
- Initial Android isolated build passed in 4m 47s. The APK contains production
  Kotlin and real dependencies under a non-launchable disposable package; it
  excludes embedded-runtime/native packaging and is not a shipping App.
  Log: `build/mqtt-chunk-state-isolated-v1.log`.
- S20U / SM-G9880 / Android 13 / `R5CN319CESA`: initial 85 tests passed in 18.016s.
  There are 68 prior cases, 11 new persistent state cases and six new actual
  Android helper/pool/route/AEAD cases. Log:
  `build/mqtt-chunk-state-s20u-v1.log`. These are not 85 real model/MQTT tasks.

The new Android helper tests use actual pair AEAD, current-generation ingress,
physical publication selection, route persistence, production WAL/FULL SQLite,
and business-inbox proofs. Physical MQTT sockets are controlled fakes; the final
Signal-to-inbox callback is a deterministic test handoff, not cross-device
native Signal acceptance. Desktop exchange tests similarly use the actual
bridge and AEAD with controlled physical brokers and a durable Signal fixture.

The initial expiry-backlog test used a list expectation against an existing
tuple-returning Python query API. That test-only expectation was corrected;
the store behavior and production checks were not relaxed.

Final target-expiry verification:

- Desktop focused regression: 122 passed in 54.749s; log
  `build/mqtt-chunk-state-python-v5.log`.
- Expanded Desktop regression: 216 passed in 44.183s, adding pool, policy,
  inbound serialization, route persistence, phone-tool routing and diagnostics.
  Log: `build/mqtt-chunk-state-python-regression-v1.log`. These suites overlap;
  their counts must not be added together as distinct cases.
- Final isolated Android build passed in 5m 9s; log
  `build/mqtt-chunk-state-isolated-v2.log`.
- S20U final run: 86 passed in 16.253s, including the new 300-expired-row
  backlog test. Log: `build/mqtt-chunk-state-s20u-v2.log`. The initial 85 cases
  are included in these 86, not 171 distinct tests.
- Actual process-stop recovery: prepare passed in PID 30636 (0.303s), then
  force-stop of only the verification package and a no-PID check, followed by
  verify in PID 30674 (0.473s). The new process recovered fragment zero,
  selected only fragment one, retained its prior `emqx` attempt, reconstructed
  the wire and released it through matching proof. Logs:
  `build/mqtt-chunk-state-process-prepare-v1.log` and
  `build/mqtt-chunk-state-process-verify-v1.log`. This is one two-phase scenario,
  not a power-loss test or two independent restart scenarios.

Only S20U was operated. Both disposable verification packages were removed after
testing; pre-existing `com.galaxyssi.chat.test` was not changed. The production
App was absent and was not installed, reset or re-paired. Running Desktop was
not replaced. No operation was performed on the connected SM-T575.

Ordinary Gradle-output isolated APKs were removed only after absolute path,
package ID and retained SHA-256 checks. Non-shipping artifacts remain under
`build/artifacts/mqtt-chunk-state-s20u-v2/`:

| Artifact | SHA-256 |
| --- | --- |
| `verification-app.apk` | `FDF802AECEE567DF7DE3CEA3F07322E9B893E8B12233D0EA7050CBA7BF672ECB` |
| `verification-test.apk` | `92C245090832EB70D38D93D4F9AE874D586765E8782243241203C531E0591215` |

Their inherited base version 1.1.110 (996) is not a release/version bump.
Normal Android configuration was restored and 93 focused unit tests passed in
3m 45s with zero failures/errors/skips: Link protocol 35, wire chunking ten,
chunk state codec six, delivery dispatch 18, peer routes 20, traffic policy four.
Log: `build/mqtt-chunk-state-normal-v1.log`. This includes recompilation of the
actual main Kotlin but excludes embedded-runtime packaging/native generation;
it is not a full-runtime APK build. The existing 153600-byte Kotlin source limit
and staged whitespace checks also passed.

## Remaining Acceptance

This advances fragment transport but does not finish the full multi-broker goal.
Remaining work includes window-coalesced bitmap feedback, throughput-informed
striping, finer retry/probe timing, coordinated retention/quotas and revocation
cleanup, all application attachment and Blob paths, real native Android/Desktop
and App/App pairing, controlled broker failures and large-file matrices, ten
real windows/background lifecycle, resource/power measurements, full-runtime
APK packaging, coordinated Android/Desktop versions and installation, main
synchronization and PR. No public broker was load-tested by these tests.
