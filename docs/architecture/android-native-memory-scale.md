# Native graph scale measurements and transaction cache

Android 1.1.75 / native memory 0.4.1 adds a bounded transaction-local node cache
and a resumable, full-graph benchmark. This is not 100M-record acceptance.

For subsequent versioned SQ8/FP16 storage and its quality/performance trade-offs,
see [compact memory nodes](android-memory-compact-nodes.md). The measurements below
remain the original FP32 baseline, not the later compact representation.

## Cache ownership

Distance calculation, neighbor expansion, graph pruning and edge updates can
read the same encrypted node repeatedly inside one stable SQLite snapshot.
The native store now retains a bounded direct-mapped cache for that transaction.
Cache collisions cause rereads, not missing results. Successful writes replace
the cached node; failed writes poison the transaction as before.

The configured cache target is shared with SQLite: keep at least one 16KiB pager
per database, assign up to a quarter of the remaining target to nodes (at most
4MiB), and leave the remainder for pagers. A too-small budget disables the node
cache. Slot count and worst-case vector/edge payload accounting do not depend
on corpus cardinality. These are cache targets, not a whole-process RSS limit.

Every read, including a hit, validates the active lease and cancellation first.
Commit, rollback, failed/cancelled completion and dropped sessions release the
cache. `Node` owns zeroizing vectors and edges; no plaintext node cache survives
into a new transaction. A new snapshot reads/authenticates persisted data again.
Source provenance/deletion/access checks are unchanged. Ciphertext format and
index identity remain unchanged, so existing derived indexes can be reopened.

## Reproducible scale probe

`tools/dev/benchmark-memory-native.ps1` builds a frozen, labelled ARM64 executable
from locked sources and checks 16KiB ELF alignment. Device modes enforce SM-T575.
Fixtures are isolated under `/data/local/tmp/galaxyssi-native-scale-*`; they never
read App databases, keys, models or settings. No model download is required.

```powershell
./tools/dev/benchmark-memory-native.ps1 -Mode build -Label candidate
./tools/dev/benchmark-memory-native.ps1 -Mode grow -Label candidate -Fixture candidate-v1 -Rows 1024 -Batch 64
./tools/dev/benchmark-memory-native.ps1 -Mode measure -Label candidate -Fixture candidate-v1 -Rows 1024
./tools/dev/benchmark-memory-native.ps1 -Mode grow -Label candidate -Fixture candidate-v1 -Rows 1056 -Batch 1
./tools/dev/benchmark-memory-native.ps1 -Mode grow -Label candidate -Fixture candidate-v1 -Rows 10240 -Batch 64
./tools/dev/benchmark-memory-native.ps1 -Mode measure -Label candidate -Fixture candidate-v1 -Rows 10240
```

The probe generates unique-ID, normalized 512D synthetic clustered vectors
incrementally and uses the actual encrypted graph/replay path. Bounded replay
pages commit vector nodes, edges, source provenance and the source checkpoint.
Interrupted growth can continue from its persisted pending event. No array of
the full corpus is created and no metadata counter substitutes for physical rows.

Each measurement process reopens the persisted index, runs 32 held-out queries
with breadth 256/top-eight results, checks source identities and result scores,
and compares to a streaming exact top-eight oracle over the complete corpus.
It then reads and verifies every persisted vector. Generation, exact-oracle work
and full verification are outside timed ANN calls and reported separately.
This synthetic geometry is not a real embedding-quality corpus.

All raw latency samples, slow runs and recall counts are retained. A 64-vector
replay-page latency is not a single-memory-write latency; `-Batch 1` measures
one independently published vector source per sample. Timings include native
encryption, graph work and durable commit, but not Android scheduling, JNI,
embedding inference, authoritative-source mutation, or UI. OS caches are not
dropped: process reopen is not a cold-storage guarantee.

## Device evidence, 2026-09-11

Only SM-T575 was operated. All runs used four shards and an 8MiB configured
cache target. Baseline is native 0.4.0; the candidate adds the transaction cache.
The graph data and search parameters are unchanged.

| Measurement | Baseline | Transaction cache |
| --- | ---: | ---: |
| Build 1,024 real vector nodes, 64 per replay page | 38.170s | 19.058s |
| Query P50 on the same 1,024-node baseline graph | 46.728ms | 47.654ms |
| Query P95 | 52.429ms | 48.679ms |
| Query P99 | 70.713ms | 76.407ms |
| Exact held-out top-eight recall | 256/256 | 256/256 |
| 32 individually committed vector sources after 1,024 nodes, P95 | 253.162ms | 198.179ms |
| Individual write maximum | 255.459ms | 211.212ms |

| Larger graph measurement | Baseline | Transaction cache |
| --- | ---: | ---: |
| Grow from 1,056 to 10,240 nodes, 64 per replay page | 579.958s | 400.021s |
| Query P50 on the same 10,240-node baseline graph | 48.012ms | 46.131ms |
| Query P95 | 56.429ms | 56.064ms |
| Query P99 | 60.141ms | 59.422ms |
| Exact held-out top-eight recall | 256/256 | 256/256 |
| 32 individually committed sources after 10,240 nodes, P50 | 187.426ms | 161.458ms |
| Individual write P95 | 210.028ms | 200.528ms |
| Individual write maximum | 233.398ms | 208.635ms |
| Final 10,272-node graph, query P95 on each own fixture | 58.147ms | 57.704ms |
| Final 10,272-node graph, query P99 | 60.955ms | 59.319ms |
| Final process peak RSS | 15,660KiB | 14,744KiB |
| Final fixture bytes | 34,996,224 | 34,996,224 |

Both retained fixtures contain 10,272 non-root vector nodes, and every vector
was read back and verified after process reopen. A 64-vector source is not 64
independent documents or memories. The separately committed 32-source phases
do test independent source publication.

Construction took about 50% less time at 1,024 nodes and 31% less time for the
larger increment in these sequential runs. This is not proof of a universal
latency benefit. Single-source write outliers still exceed 200ms; 64-vector
replay pages still take seconds, not milliseconds.

One candidate run immediately after construction of its own 10,240-node graph
was slower: query P50/P95/P99 were 108.142/131.758/139.901ms. Its exact oracle
and full verification were also slower. The cause was not isolated, so this
run is retained rather than attributed to a proven thermal or CPU condition.
All scale runs returned 256/256 held-out top-eight matches.

[Structured evidence](android-native-memory-scale-20260911.json) retains all
15 grow/measure runs, raw samples, counts and frozen binary hashes. The baseline
and candidate binaries were frozen before the version bump; candidate production
cache code is the code shipped in native 0.4.1. A subsequent harness-only guard
rejects growth targets below an already committed row count.

## App and regression verification

- SM-T575 reports App 1.1.75, versionCode 961 after data-preserving installation.
  APK SHA-256: `88f20f2827bab4c215857433b471cd2d1876d5962fe5796e4abdaeddc75e1047`.
- Gradle unit tests: 3,686 cases, zero failures/errors, five skipped. Debug App
  and instrumentation APK builds passed; all 74 native libraries passed the
  16KiB alignment audit.
- Actual-device native SQLite suite: 23 passed, one intentional crash-child
  helper ignored. Includes cache eviction, a zero-cache budget, cancellation,
  rollback, cross-snapshot authentication, process death and replay recovery.
- Installed-App instrumentation: 18 passed across direct JNI, source replay,
  hybrid lifecycle/filtering/cancellation and real Chinese BGE retrieval.
- Existing pinned BGE fixture, no download: three expected passages matched;
  100 queries measured P50/P95/P99 of 150/207/234ms. This small real-model case
  does not establish a 200ms end-to-end guarantee or large-corpus neural recall.
- The first App instrumentation attempt overlapped an unfinished APK install;
  PackageManager stopped the old process during replacement. That attempt is
  invalid. The 18 passing cases above were rerun after installed-version checks.
- Native host core regressions passed (10 cases). The new all-features host
  CLI integration case and cache unit cases are included in Linux CI; they were
  not executed by the local Windows core-only test command. The scale executable
  itself was exercised on SM-T575 with the full persisted graphs described above.

The existing compatible instrumentation package was reused against the verified
new App installation. No App reset, re-pairing, production data extraction,
model replacement or operation on another connected device was performed.

## Remaining scope

The required 100M+ corpus, summary routing/PQ, metadata partitioning, automatic
repair, compaction/deletion residue and end-to-end App performance acceptance
remain open. Raw 512D FP32 vectors alone would exceed 190GiB at 100M rows before
graph and metadata overhead; this representation is not the final mobile-scale
architecture. The benchmark makes the current limits measurable rather than
claiming that a small successful fixture demonstrates the full goal.

Foreground query admission also remains open: `KnowledgeSemanticSearch.search`
can synchronize up to four native replay pages under a lock shared with indexing.
The measured multi-second replay pages show why a query with pending indexing
can miss its latency budget before lexical fallback. A separate follow-up must
make foreground readiness nonblocking and leave replay to background indexing,
with a backlog regression, rather than treating the fast ready-index numbers
above as a solution to that path. This PR does not change Kotlin admission logic.
