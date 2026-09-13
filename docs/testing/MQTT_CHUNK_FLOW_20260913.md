# MQTT Chunk Feedback and Adaptive Scheduling

Date: 2026-09-13. Development checkpoint; full P2/P3 acceptance remains open.

## Runtime

The Android and Desktop actual chunk publication descriptors now carry bounded,
process-local observations into their existing multipath policies. Only a
successfully committed current, authenticated bitmap can credit peer delivery.
Pending chunk load remains visible after a Broker PUBACK. Unambiguous first
attempts feed an EWMA; ambiguous/retried, cross-pair/query or stale-generation
receipts cannot teach the scheduler that a path is fast.

The score combines peer latency and estimated queued delivery time rather than
fixed thirds or brand priority. Measurements use final encoded MQTT wire bytes
and include receiver/feedback/return delay. They are not measured raw bandwidth
or decoded attachment goodput. Sparse observations retain a configurable cold
estimate; expiry and network/pair changes discard obsolete local statistics.

Receiver partial states coalesce within a bounded window and flush from the
existing maintenance tick. Complete and probe states remain immediate. No new
per-peer thread, permanent timer, unbounded packet queue or durable message
ledger was added. Durable outbox/inbox and chunk-state stores still own retries,
deduplication and business receipt semantics. See the
[protocol](../protocol/MQTT_MULTIPATH.md#wire-fragment-state-exchange) for limits.

## Verification

| Scope | Result | Evidence |
| --- | --- | --- |
| Pure JVM policy/route/codec tests | 190 passed, 4.382s | `build/mqtt-chunk-flow-host-v2/tests.log` |
| Backend initial focused run | 105 passed, 6.688s | `build/mqtt-chunk-flow-python-v2.log` |
| Backend expanded regression | 228 passed, 26.880s | `build/mqtt-chunk-flow-python-regression-v1.log` |
| Catalog generation/negative checks | 5 passed, 0.146s | `tools.test_generate_mqtt_catalog` |
| Isolated Android build | Passed, 3m 11s | `build/mqtt-chunk-flow-isolated-v1.log` |
| S20U instrumentation | 87 passed, 18.518s | `build/mqtt-chunk-flow-s20u-v1.log` |
| Ordinary Android focused unit tests | 105 passed, zero failures/errors/skips, 6m 36s build | `build/mqtt-chunk-flow-normal-v1.log` |
| Source-size check | Passed, 153600-byte Kotlin limit | `tools/quality/check-kotlin-source-size.mjs` |

Suites and prior checkpoints overlap; do not add their counts as unique tasks.
The Python pair-isolation test was tightened to use monotonic observation order
and prove both pairs exist before revocation; no production check was relaxed.

S20U was SM-G9880 / Android 13 / serial `R5CN319CESA`. The instrumented suite
includes seven actual Android chunk-helper/pool/route/AEAD cases, up from six.
The burst-completion test now expects one terminal state rather than one state
per fragment. A new case verifies no immediate partial response, flush after
the configured window, and an immediate subsequent probe response.

The actual process-stop scenario prepared state in PID 589 (0.301s), force-stopped
only the disposable verification package, checked no live PID, and verified in
new PID 747 (0.476s). The new process retained the stored fragment and prior
attempt metadata and selected only the missing fragment. Logs:
`build/mqtt-chunk-flow-process-prepare-v1.log` and
`build/mqtt-chunk-flow-process-verify-v1.log`. This is one two-phase scenario,
not a power-loss test or two independent recovery cases.

Instrumentation uses real production Kotlin, AEAD and WAL/FULL SQLite but
controlled physical MQTT callbacks and a deterministic Signal-to-inbox handoff.
It does not prove a native cross-device Signal exchange or a model task.

Both owned verification packages were removed after tests. The pre-existing
`com.galaxyssi.chat.test` package was untouched; the production App was absent.
No operation was performed on the connected SM-T575 or on S26U. Running Desktop
was not replaced. Ordinary Gradle-output isolated APKs were removed after
absolute-path, package and retained SHA-256 checks; non-shipping copies remain:

| Artifact under `build/artifacts/mqtt-chunk-flow-s20u-v1/` | SHA-256 |
| --- | --- |
| `verification-app.apk` | `E422AD7133634F3354213B9ADF8E03BB9C71ADA60A3A032B047240BE47194911` |
| `verification-test.apk` | `624B7E4E7792260F548DAC0DE2803FE186B851CF4924E33150B11163B1081A83` |

Their inherited 1.1.110 (996) is not a release version bump. The normal unit-test
build restored ordinary configuration but excluded embedded-runtime/native
generation; it is not a full-runtime shipping APK.

## Owned TCP/TLS Smoke

The new [owned lab](../../tools/testing/mqtt_owned_lab/README.md) starts three
independent, loopback-only aMQTT 0.12.0 TLS listeners with an ephemeral test CA.
The real Desktop pool, policy, authenticated resume, Paho callbacks, pair AEAD
and isolated SQLite route persistence run over real TCP/TLS. There is no public
broker traffic, DNS/config mutation, system CA installation or disabled TLS.

Final smoke passed two negative certificate cases and ten synthetic directed
messages: both directions over each of three paths, automatic communication
with one broker stopped, and communication over that path after restart and
authenticated resubscription. All owned workers/listeners shut down afterward.
Log: `build/mqtt-owned-lab-smoke-v3.log`. Observed high-resolution receive times
were 0.901-1.340ms on local loopback, **not** internet latency or p50/p95 claims.

The first fixture incorrectly restricted authorization without selecting that
path in the scheduler; it was corrected, not production routing. The first
successful report used a coarse Windows monotonic clock; the final report uses
`perf_counter`. These changes and limits are recorded in the lab README.

## Remaining Work

Full-runtime Android/Desktop packaging and coordinated versions/install were
subsequently completed in the [S20U deployment](MQTT_DEPLOYMENT_S20U_20260913.md).
Real scan/pairing remains next. Continue with native Signal and durable
business acceptance over owned sockets, real image/file/video artifact hashes,
preview/open/save, App/App pairing, complete outage/restore and loss/latency
matrices, attachment retry timing and quota/revocation cleanup, ten real windows,
background/Doze/reboot, controlled performance/power measurements, main sync and
PR. The lab is infrastructure for those tests, not a substitute for them.
