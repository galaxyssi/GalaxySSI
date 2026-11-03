# Reply delivery and reconnect overhead

This follows PR #3635. The acceptance interval remains **Desktop model completion
to the phone drawing the final reply**, not total model inference time.

## Baseline

The first real S26 Ultra request after reconnecting measured 3,935 ms (clock
sampling uncertainty 28 ms): Desktop preparation 1,019 ms, downlink about 330 ms,
and phone reception-to-display 2,586 ms. The reply was produced by real Codex.

A Python sampling profile showed final publication waiting for the global
outbound lock and spending time reopening and initializing the delivery DB.
Every warm open repeated 28 schema/setup statements. The new fast path uses five
statements, retaining WAL and FULL synchronization. Its durable marker is bound
to the SQLite schema cookie, initialization contract, and migration markers.
External DDL, database replacement, missing migration markers or contract upgrades
force revalidation. It does not cache pairing secrets or message plaintext.

An isolated 30-open microbenchmark under concurrent build load did **not** show a
wall-time improvement (medians 1.955 ms before and 2.800 ms after). Reduced SQL
work alone is not evidence of meeting the end-to-end target.

After builds stopped, an alternating baseline/updated run (60 opens each, same
temporary database) measured medians 1.661 / 1.431 ms and maxima 2.968 / 3.068 ms.
This is a small per-open reduction, not an end-to-end latency claim.

## Android reconnect leak

The running phone had 422 threads. A short ART sampling trace listed 301 MQTT
threads; old connection stacks were sleeping inside Paho `CommsCallback.start`
and `CommsSender.start`. Paho 1.2.5 waits to observe RUNNING even when the worker
already started and stopped. Repeated failed connections can retain those
connection threads indefinitely.

The `paho-runtime` module keeps the original API and all unmodified upstream
classes. Only the three worker startup waits change: return when their target
state is STOPPED, and respect interruption. No certificate validation, encryption,
broker selection, protocol limits, retry budget or durable delivery behavior is
relaxed. Original license notices are retained.

## Regression evidence

- Backend database initialization, result outbox, durable MQTT delivery and
  Signal receive tests: 100 passed.
- The same nine Java lifecycle tests against unmodified Paho: six failed.
- Against the patched runtime: all nine passed, including 96 rapid worker exits.
- Android MQTT routing, pool, delivery, receipt, chunking and traffic policy
  regressions: 253 passed across 19 suites.
- Packaged JAR: all 110 runtime classes retained, 104 byte-for-byte unchanged,
  six replaced worker/enum classes, and no duplicate ZIP entries.
- The first APK exposed a packaging regression in the new project dependency:
  Android selected its classes directory and included only the six replacements.
  A real installed-device test failed with `NoClassDefFoundError`. The explicit
  `packagedRuntime` artifact fixes this; the rebuilt APK defines all 110 classes
  exactly once and the installed-device connection test passes.
- Final device regression: 24 MQTT 3.1.1 probes all reached a loopback TCP
  server, were rejected, and released their worker threads. The server accept
  count is asserted so an early dependency or permission error cannot pass.

The phone APK retains the unrelated news changes already present in the shared
checkout. Those news changes are not part of this PR. No app data, pairing,
models, messages or user tasks are cleared.

## Versions and live verification

Android: 0.1.6.26 (1402). Desktop: 0.1.6.7.

The updated app reconnects and real Codex replies reach the phone. During more
than 40 rejected Mosquitto reconnects, the sampled MQTT worker count remained
small (six in one sample), rather than the baseline 301. HiveMQ was operational;
EMQX was timing out and Mosquitto was closing the connection. This is not evidence
that all three public brokers are healthy, nor a long-duration leak certification.

Initial real-reply samples, milliseconds:

| Sample | Desktop completion to wire | Estimated downlink | Phone receive to draw | Completion to draw |
| --- | ---: | ---: | ---: | ---: |
| P, concurrent host build | 1437 | 347 | 3229 | 5012 +/- 43 |
| Q, Android sampling enabled | 1895 | 339 | 1666 | 3900 +/- 35 |

These diagnostic samples are not quiet-device acceptance measurements. In Q,
ART sampling attributed substantial phone completion work to repeated encrypted
task/history reads and writes through Android Keystore. Encryption and durable
completion ordering have not been weakened to improve the number.

The stable three-second completion-to-display target remains unproven. Model
execution is measured separately and is not included in that target.

After all builds and profiling stopped, sample R (fresh app process) measured
4,520 +/- 19 ms: Desktop preparation 1,349 ms, downlink 349 ms, phone display
2,821 ms. Warm sample S measured 4,085 +/- 22 ms: preparation 1,586 ms, downlink
363 ms, phone display 2,135 ms. A third warm sample T measured 5,005 +/- 31 ms:
preparation 2,451 ms (including 881 ms transport queueing), downlink 400 ms,
phone display 2,154 ms. All were real completed Codex replies; none meets the
three-second target, and this series does not demonstrate a latency improvement
over baseline. The restart test preserved the original app
installation, pairing and data (first installed September 13).
