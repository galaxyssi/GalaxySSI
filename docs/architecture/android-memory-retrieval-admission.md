# Foreground native memory retrieval admission

Android 1.1.87 follows the user-reserved 1.1.84 version and the rejected
1.1.85/1.1.86 device candidates, even when the reserved version
has not yet merged into main. Recheck upstream versions before publishing or
installing; do not infer the latest delivered version from main alone.

## Problem

In 1.1.75, each foreground semantic query acquired the same blocking monitor
as background replay and synchronously applied up to four replay pages before
falling back to lexical retrieval. The real SM-T575 scale probe measured native
64-vector replay pages taking seconds. A ready-graph search benchmark did not
cover this queueing delay.

## Changes

- Query admission uses a fair index-owner lock with at most 25ms of waiting for
  short cleanup/checkpoint handoffs. If replay or another query still owns it,
  the caller uses existing authoritative FTS/lexical retrieval. There is no
  unbounded wait for native replay or another encoder invocation. Uncontended
  queries do not sleep or spend a mandatory 25ms.
- A foreground readiness check reads feed/checkpoint metadata and can reopen
  a previously committed authenticated graph. It cannot register a model,
  backfill source events, seed a graph or append vectors.
- Missing or lagging derived indexes request coalesced background replay.
  Existing durable WorkManager indexing remains active, including after restart.
- Native query vectors are still cleared, lifecycle invalidation stays
  nonblocking, and current source revision/access/deletion checks still run
  before dense results can be published.
- A fallback releases the native owner before reading the lexical store.
- Vector-page reads copy a bounded encrypted snapshot under the database lock,
  decrypt outside it, and revalidate the source revision and authenticated
  checkpoint before publication. Cancellation is checked between frames; both
  ciphertext copies and rejected plaintext are cleared on all exits.
- Resume work records the session generation at enqueue time. A query or durable
  worker that has already reopened that generation makes the queued resume work
  obsolete. Already-current native indexes do not perform a redundant replay.
- An empty source does not skip pending deletion events in an existing graph.

The gate does not make all retrieval constant-time. Source-database access,
query-model loading/inference, cold index open and native search still have
their own costs. A query during replay can have lexical-only results; complete
concurrent ANN snapshots and large-corpus end-to-end recall remain separate
requirements. This change does not claim 100M acceptance.

## Focused verification

`KnowledgeRetrievalAdmissionDeviceTest` checks:

1. Readiness leaves an unbuilt feed/index unchanged, reopens a committed graph,
   refuses stale source revisions, and does not silently re-register a model.
2. A query with an unbuilt graph schedules replay without invoking its query
   encoder; later retrieval uses the completed native graph.
3. Thirty-two lexical queries remain responsive while the actual replay owner
   is held at its cancellation boundary. Releasing it allows real replay and
   semantic retrieval to complete.
4. A second query does not queue behind a slow encoder; deletion during the
   first query cannot return an obsolete dense match.
5. A real 512D, multi-page encrypted replay runs while foreground lexical
   queries are measured. All native work is then completed and queried again.
6. Blocking a page at its decryption boundary does not block source queries;
   replacement, deletion and model removal invalidate that captured page.
7. Cancellation after decryption prevents publication without damaging the
   authoritative encrypted source.

The latch case makes ownership contention reproducible; it is not presented as
real disk throughput. The separate full-width replay case has no injected native
delay. Both retain raw foreground latency samples and target a maximum below
200ms on SM-T575. Lifecycle, hybrid permissions, corruption, TTL and real BGE
regressions remain part of validation. Fixtures use separate databases and do
not change model downloads, pairing or production messages.

## Validation status

### Preserved baseline and rejected candidate

SM-T575, isolated synthetic databases, 32 foreground queries per case. The real
replay corpus contains one `orchard` source and 512 generated backlog records,
encoded into 512D vectors. Native replay has no artificial delay in that case.

| Build / case | P50 ms | P95 ms | Max ms | Outcome |
| --- | ---: | ---: | ---: | --- |
| 1.1.75 / actual 512D replay | 59 | 72 | 2965 | Failed 200ms target |
| 1.1.85 / actual 512D replay | 24 | 52 | 315 | Failed 200ms target |
| 1.1.75 / controlled replay ownership | 63 | 126 | 15521 | Blocked behind owner |
| 1.1.85 / controlled replay ownership | 24 | 32 | 46 | Passed |
| 1.1.85 / slow encoder ownership | 25 | 36 | 41 | Passed |

The controlled ownership case deliberately holds a latch for up to 15 seconds;
its 15.5-second baseline is not a disk latency measurement. Baseline APK SHA256:
`88f20f2827bab4c215857433b471cd2d1876d5962fe5796e4abdaeddc75e1047`.

The 1.1.85 candidate passed 21/23 focused device tests and failed both the actual
replay maximum and the foreground-resume semantic-result assertion. It was not
accepted. Its separate 100-query BGE run passed 3/3 passage recall with
P50/P95/P99 of 138/179/194ms; this small ready-index run does not establish
large-corpus acceptance. APK SHA256:
`c29e8df6b136a6e4783b1c5b6883bf4f89e99e9822503b2ae07a2c2cf0230d72`.

Local logs retain raw measurements in `build/native-admission-v1175-baseline.log`,
`build/native-admission-v1175-real-replay-baseline.log` and
`build/native-admission-v1185-device.log`.

### Rejected 1.1.86 candidate

The real 204-chunk, 512D replay case measured P50/P95/max of 24/34/36ms, and its
native replay completed in 3295ms. All foreground timing cases passed. However,
23/25 focused device tests passed: full-width nonlexical recall after replay
returned a `busy` lexical fallback, and a 50ms-TTL ownership handoff also returned
empty. The generation-aware resume case passed. These results demonstrated that
zero-wait admission was too aggressive even for short maintenance handoffs.
The candidate was not accepted. APK SHA256:
`0a73618d5b14b894945d2b548f3504961b09ea28908b6ae18fa4a5aa7d8f40d9`.

The database/page changes separately passed all 25 ledger/change-feed device
tests in 95.881 seconds, including 1201 real encrypted synthetic documents,
and three offline BGE/WorkManager lifecycle tests in 19.036 seconds. These cover
automatic indexing and ordinary RAG, controller recreation with pending work,
and a 40-document burst. They reused the existing pinned local BGE fixture, not
a network download or production-model replacement. The focused 100-query BGE
measurement was 138/180/188ms at P50/P95/P99 with 3/3 passage recall.

### 1.1.87 validation

Android 1.1.87 (code 973) was installed with `adb install -r` on SM-T575 and its
installed package version was verified before instrumentation. Main and test
APKs came from the same completed offline build. APK SHA256:
`57bd72b5f9b8a52c554f5e9f01d000a2d0c538dc8f6c3c8f38b67cd99a755d71`.
Latest merged main `65655f0c7` was included, preserving PR #3007.

- Build and all 3730 unit cases: no failures/errors, five existing skips.
- Native packaging: 74/74 AArch64 libraries passed 16KiB alignment.
- Initial 50-test device suite: 49 passed; a single 226ms controlled-owner
  query failed the unchanged strict maximum-under-200ms assertion. Semantic
  recall after replay, foreground resume and the 50ms TTL case all passed.
- Without changing code or assertions, eight subsequent rounds of four tests
  passed (32/32). Every round includes actual full-width replay, controlled-owner
  admission, TTL handoff and foreground resume.
- Final complete device run: 53/53 passed in 159.719 seconds, including all
  ledger/change-feed regressions and three real BGE/WorkManager lifecycle tests.
- Across initial, repeat and final admission runs: 895/896 samples below 200ms,
  P50/P95/P99 of 64/77/83ms, maximum 226ms. The 226ms sample is retained, not
  excluded or attributed to an unproven cause. The strict per-call target is
  therefore **not universally satisfied**.

| Admission phase, all retained runs | Samples | P50 ms | P95 ms | P99 ms | Max ms |
| --- | ---: | ---: | ---: | ---: | ---: |
| Actual 204-chunk, 512D replay | 320 | 60 | 77 | 83 | 96 |
| Controlled replay owner | 320 | 70 | 79 | 86 | 226 |
| Slow encoder owner | 64 | 70 | 76 | 80 | 80 |
| Page decryption / replace | 64 | 20 | 29 | 73 | 73 |
| Page decryption / delete | 64 | 25 | 32 | 40 | 40 |
| Page decryption / unregister | 64 | 16 | 26 | 27 | 27 |

The final ordinary-store BGE run achieved 3/3 passage recall over 100 queries,
with P50/P95/P99 of 135/179/208ms. The initial same-build run was 133/176/183ms.
The slower final P99 is retained. This is a three-passage, warm-model regression,
not the foreground-fallback probe above, not a cold-load bound, and not 100M
end-to-end acceptance. No model download, ASR/QNN change, pairing reset or
production-memory replacement was performed.

[Machine-readable raw admission samples](android-memory-retrieval-admission-20260912.json)
include every sample from all ten 1.1.87 instrumentation processes. Local raw
instrumentation logs are `build/native-admission-v1187-device.log`,
`build/native-admission-v1187-repeat-1.log` through `-8.log`, and
`build/native-admission-v1187-final-device.log`. Assertions were not relaxed.

The change removes demonstrated seconds-long waits and correctness failures
at short ownership handoffs. Large-scale partitioning, compressed vectors,
concurrent ANN snapshots and strict end-to-end tail latency remain open work.
