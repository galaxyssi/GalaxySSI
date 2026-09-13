# Native Small-Message Latency And Adaptive Hedge

Date: 2026-09-13. Branch: `feat/automatic-multi-broker-20260912`.
The full Android/Desktop multi-broker goal remains open.

## Method

`tools/testing/mqtt_owned_lab/native_latency.py` runs two independent real Signal
JVM/Python/SQLite endpoints against three owned loopback TLS brokers. No public
broker, production account, phone, model or user conversation participates.
Local host model: 21AJS0DE00, 16 logical processors, 51,190,489,088 bytes RAM.
The desktop is not a CPU-isolated benchmark host; unrelated host activity is not
controlled. Do not interpret these results as Internet/provider performance.

Each run measures 30 messages with one available path and 30 with automatic
multi-path scheduling. Each single-path block uses a different owned broker
label. Six seeded blocks each have one excluded warm-up and ten measured
messages, giving 66 business messages whose exact identity, hash, ownership,
durable receipts and one completed business dispatch are checked.

The single-path baseline uses the same production pool/window with two owned
listeners stopped. It is not a one-connection resource benchmark or a historical
binary comparison. All three receive connections remain the normal multi-path
configuration; there is no product default broker or user mode selector.

Histories, ratchets and application caches are retained within each run. New
runs get new identities and disposable stores. TLS/startup and block transition
plus warm-up are separate from measured requests. JVM/identity startup is not
included in the transport-startup clock. Startup has only one observation per
endpoint, not a cold-start percentile distribution.

The opt-in bounded measurement helper records monotonic timestamps inside the
sender at request entry, return from the actual durable queue commit, first
accepted physical submission, and return from the authenticated receipt commit.
The latter is after the outbox proof check, optional projection and SQLite
commit. PUBACK does not stop this clock. Polling reads an in-memory copy, not
chat history; late polling cannot inflate the captured interval.

The initial harness failed because it immediately equated RX_STORED with a
completed chat handler. The captured final handler was still running, with no
ingress error. Business projection is now separately awaited and checked after
each measured block; that wait does not change the RX_STORED timestamp. A failed
or censored sample fails the run and is retained, never scored as zero latency.

Byte totals count submitted business MQTT frames, including topic/protocol and
existing encryption/privacy padding. They exclude TLS/TCP headers, handshake,
ACK/control traffic and retransmission below the pool. They are not NIC byte
counts. No compression, padding, original-image or encryption policy changed.

## Baseline

Nearest-rank percentiles, milliseconds. Counts below are per strategy, not a
sum of repeated test suites.

| Run/strategy | n | Request to RX_STORED p50 | p95 | Business frames |
| --- | ---: | ---: | ---: | ---: |
| Seed 20260913, single available | 30 | 1383.68 | 2184.36 | 30 |
| Seed 20260913, automatic multi | 30 | 1623.11 | 3390.47 | 63 |
| Seed 20260914, single available | 30 | 1541.10 | 1975.08 | 30 |
| Seed 20260914, automatic multi | 30 | 1898.91 | 3092.09 | 66 |

Evidence: `build/mqtt-native-latency-v{2,3}-20260913/report.json`.
Both runs passed all 66 business checks. The original startup observation hook
could be read before its next tick and produced null; these are unavailable
measurements, not zero. The new hook captures first authenticated readiness at
the existing route callback as well as the maintenance fallback.

## Symmetric Scheduling Change

The previous scheduler required 20 verified receipts on the first-ranked path
before replacing its 500ms cold-start hedge delay. Rotating traffic across three
paths could leave each path below that threshold even after many messages. The
same receiver/crypto/storage cost then repeatedly triggered unnecessary copies.

Android and Desktop now use the current peer's recent receipts across eligible
healthy common paths when the selected path has fewer than 20 samples. The
combined set still needs 20 verified samples. Once the selected path has its own
full sample window, that path's percentile takes precedence. The existing p90
multiplier, delay bounds, TTL, network-change reset and bounded per-path history
are unchanged. No statistics cross peer boundaries. Offline/non-common paths do
not contribute. Small stop/cancel controls still race immediately; progress and
chunk traffic are unchanged.

The deterministic pre-fix test showed the old 500ms delay after 20 receipts
distributed across three paths, where the measured 800ms baseline should yield
1200ms. New mirrored tests cover the threshold, control priority, exclusion of a
failed path, peer isolation and network resets.

## Post-Change Observation

Same seed 20260914, new disposable endpoints; no compile/load test ran alongside
the latency measurement. Host scheduling is not otherwise isolated.

| Strategy | n | Request p50 | Request p95 | Publish to RX_STORED p95 | Frames |
| --- | ---: | ---: | ---: | ---: | ---: |
| Single available | 30 | 1605.36 | 3248.35 | 2556.53 | 30 |
| Automatic multi | 30 | 1386.32 | 2174.39 | 1890.55 | 30 |

Both strategies submitted 658,020 measured business MQTT bytes. Multi-path had
zero redundant submitted business frames in this run, versus 789,624 redundant
bytes in the same-seed pre-change run. The selected path reflects local observed
statistics; its broker label does not imply a fixed public-provider preference.
First authenticated-ready observations were 442.90ms and 321.32ms.

A provisional within-pool warm p95 ratio budget of 1.10 was set before the
post-change measurement. This run's ratio was 0.669 and passed that limited check.
The single-path baseline itself varied materially, so this is not proof of a
stable 33% general speed gain. Repeated post-change runs, real networks and the
remaining workload/fault matrix are still needed for the release gate.

Evidence: `build/mqtt-native-latency-adaptive-v1/report.json`.

## Repeated Order Revealed A Remaining Failure

Seed 20260913 was repeated after the first post-change run, again without a
concurrent build or load test. The six blocks were single Mosquitto, multi,
multi, single HiveMQ, multi, single EMQX. Labels refer only to owned listeners.

| Strategy | n | Request p50 | Request p95 | Publish to RX_STORED p95 | Frames |
| --- | ---: | ---: | ---: | ---: | ---: |
| Single available | 30 | 1216.57 | 1845.89 | 1622.80 | 30 |
| Automatic multi | 30 | 1540.56 | 2910.29 | 2556.61 | 43 |

All 66 business checks passed, but the p95 ratio was **1.577**, failing the
provisional 1.10 budget. Multi-path submitted 943,162 business MQTT bytes,
including 285,142 redundant bytes. This is an unsuccessful performance gate,
not a passing release result. Evidence:
`build/mqtt-native-latency-adaptive-v2/report.json`.

All 13 additional frames occurred in the first multi-path block: six messages
had three submissions and one had two. The subsequent twenty measured
multi-path messages each used one submission. This localizes the remaining
redundancy to the sample-poor transition; it does not prove that redundancy is
the sole source of all latency variation. The under-twenty-sample 500ms default
is unchanged. It needs a measured cold-start/failed-fastest-path investigation,
not a lower sample threshold chosen merely to make this benchmark pass.

The two post-change runs therefore do **not** establish stable non-regression.
Do not average away the failing order or quote only the passing order. The CLI
now returns exit code 2 when the provisional gate fails while preserving the
report and separate business-correctness result. The preceding v2 invocation
used the earlier CLI, which exited 0 despite its explicit false gate field;
its report remains a failed performance observation.

## Verification And Remaining Work

- Seven measurement unit tests passed, including late polling, incomplete
  samples, nearest-rank percentiles, bounded storage and failed physical sends.
- Three CLI/sample-budget tests passed alongside those seven, ten total,
  proving a false performance gate cannot exit successfully and invalid sample
  budgets fail before any broker or file access.
- 93 focused Python policy/dispatch/route/bridge tests passed, including the
  mature-primary precedence case added after the repeated measurement.
- 195 Kotlin host transport tests passed (7.386s), including mature-primary
  precedence. These are not Android device tests.
- Normal full-runtime Android build and Android-test Kotlin compilation passed
  in 9m 1s. Its four-suite selection passed 79 JVM cases, zero failures, errors
  or skips, before adding the final precedence test. It is not a device test.
- Owned TLS/native Signal regression passed 19 business messages, including
  real subscription loss after outbox selection, all three path rotations,
  lost receipts and two-endpoint process recovery. Both endpoint logs were
  empty. Three offline API entry checks also passed; these are not phone or
  image/file/video UI acceptance. This correctness run overlapped the full
  build and is intentionally not used for latency comparison.

Full APK: `com.galaxyssi.chat` 1.2.0 (1005), 427,091,502 bytes,
SHA-256 `FA95CE5BDA6A453F442C8D552081AF6490BD4C3274956884937006BE863CA13F`.
This is the newly built artifact, not the earlier 1005 background checkpoint.
Kotlin source-size policy and whitespace checks passed.

Still required: the third strategy's real artifact/block workload; 100KB images,
boundary cases, 5MB/21MB/larger files; control latency under concurrent transfer;
fastest-path failure performance; complete task/artifact timing; cold-start
distributions; designated-device windows/lifecycle/Doze; diagnostics and
Wi-Fi/cellular/weak-network resource and power measurements. Current timing
hooks intentionally fail to summarize uninstrumented large/chunk submissions
rather than silently present small-message coverage as artifact performance.

S26U remains disconnected. SM-T575 was not operated. No production Desktop
restart or phone installation is part of this checkpoint. Public versions remain
1.2.0 in draft PR #3045; this is not final release acceptance.
